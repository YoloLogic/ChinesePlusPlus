// ============================================================================
//  ppltasks.h -- 手搓的最小 PPL 替身（§18.48 批4 补）
//
//  WHY
//    MSVC STL 的 <future> **无条件** `#include <ppltasks.h>`（vendor\msvc-stl\future
//    第 24 行）。那个头是微软的 **PPL（Parallel Patterns Library）**，而且它
//    **不是开源件** —— 文件抬头是
//        Copyright (c) Microsoft Corporation. All rights reserved.
//    （MSVC STL 其余部分是 Apache-2.0 WITH LLVM-exception；PPL 不是。）⇒ **不能随包**。
//
//    可它又不是"可选的可选件"：MSVC 的 `std::async` **就是**建在 PPL 上的 ——
//      future:621   _Task = ::Concurrency::create_task([this]() { this->_Call_immediate(); });
//      future:643   ::Concurrency::task<void> _Task;
//    ⇒ 不补它，bundled（零 VS）模式下连纯标准 C++ 的 `<future>` / `std::async`
//      都编不过（实测：`fatal error: 找不到文件 'ppltasks.h'`）。
//
//  手搓到什么程度（不多写一行）
//    把整个 STL 翻了一遍，`Concurrency::` 只出现在上面那**两处**（实测）。
//    所以这里只发 `<future>` 真正用到的那点东西：
//      · `Concurrency::task<T>`：`wait()`（阻塞到完成，并把异常重抛）与 `get()`；
//      · `Concurrency::create_task(f)`：在**另一个线程**上跑 `f`，返回 `task<R>`。
//    `wait()` 必须真异步、真阻塞、真重抛 —— 语义照微软的来，不是"能编过就行"。
//
//  明确的边界（如实写）
//    微软 PPL 的其余部分（`ppl::`、**continuation** `.then()`、`cancellation_token`、
//    `task_options`、`parallel_for`/`parallel_invoke` …）**这里没有**，也不打算假装有。
//    那些是**微软扩展**，不在 C++ 标准里；用了它们的程序会得到清楚的编译错误
//    （`no member named 'then' ...`），而不是莫名其妙的链接错误。
//    ★ 判据在 build\_review_own\batch5diag\stl_smoke.cpp：那里**真跑** `std::async`
//      并且检查返回值，不是只编过。
//
//  ASCII only（正文里出现中文字面量会被 PS 5.1 的 ANSI 解码弄坏）。
// ============================================================================
#pragma once

#ifndef _ZH_PPLTASKS_MINIMAL
#define _ZH_PPLTASKS_MINIMAL

#include <exception>
#include <memory>
#include <thread>
#include <type_traits>
#include <utility>

namespace Concurrency {

namespace zh_ppl_minimal {

template <class _Ty>
struct _Task_state {
    std::thread _Worker;
    std::exception_ptr _Error;
    std::unique_ptr<_Ty> _Value;
};

template <>
struct _Task_state<void> {
    std::thread _Worker;
    std::exception_ptr _Error;
};

template <class _Ty>
void _Wait_for(const std::shared_ptr<_Task_state<_Ty>>& _State) {
    if (!_State) {
        return;
    }
    if (_State->_Worker.joinable()) {
        _State->_Worker.join();
    }
    if (_State->_Error) {
        std::rethrow_exception(_State->_Error);
    }
}

} // namespace zh_ppl_minimal

//  task<T> -- only what <future> drives: wait() and get().
template <class _Ty>
class task {
public:
    task() noexcept = default;
    explicit task(std::shared_ptr<zh_ppl_minimal::_Task_state<_Ty>> _State) noexcept : _State(std::move(_State)) {}

    task(const task&)            = default;
    task(task&&) noexcept        = default;
    task& operator=(const task&) = default;
    task& operator=(task&&) noexcept = default;
    ~task() noexcept             = default;

    void wait() const {
        zh_ppl_minimal::_Wait_for(_State);
    }

    _Ty get() const {
        wait();
        return *_State->_Value;
    }

private:
    std::shared_ptr<zh_ppl_minimal::_Task_state<_Ty>> _State;
};

template <>
class task<void> {
public:
    task() noexcept = default;
    explicit task(std::shared_ptr<zh_ppl_minimal::_Task_state<void>> _State) noexcept : _State(std::move(_State)) {}

    task(const task&)            = default;
    task(task&&) noexcept        = default;
    task& operator=(const task&) = default;
    task& operator=(task&&) noexcept = default;
    ~task() noexcept             = default;

    void wait() const {
        zh_ppl_minimal::_Wait_for(_State);
    }

    void get() const {
        wait();
    }

private:
    std::shared_ptr<zh_ppl_minimal::_Task_state<void>> _State;
};

//  create_task(f) -- runs f on ANOTHER thread (that is what std::launch::async means).
template <class _Fty>
auto create_task(_Fty&& _Fn) -> task<std::invoke_result_t<_Fty>> {
    using _Ret = std::invoke_result_t<_Fty>;
    auto _State = std::make_shared<zh_ppl_minimal::_Task_state<_Ret>>();
    auto _Body  = std::forward<_Fty>(_Fn);
    _State->_Worker = std::thread([_State, _Body]() mutable {
        try {
            if constexpr (std::is_void_v<_Ret>) {
                _Body();
            } else {
                _State->_Value = std::make_unique<_Ret>(_Body());
            }
        } catch (...) {
            _State->_Error = std::current_exception();
        }
    });
    return task<_Ret>(std::move(_State));
}

} // namespace Concurrency

#endif // _ZH_PPLTASKS_MINIMAL
