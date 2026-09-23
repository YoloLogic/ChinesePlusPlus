// 纯英文回归测试：确认改动没有破坏英文 C++。
// 这是最重要的一项：标准库头文件全是英文关键字，此文件必须照常编译。

#include <cstddef>
#include <vector>
#include <string>

template <typename T>
class Box {
public:
    explicit Box(T v) : value_(v) {}
    virtual ~Box() = default;
    virtual T get() const { return value_; }
private:
    T value_;
};

int main() {
    Box<int> b(42);
    std::vector<std::string> v;
    v.push_back("hello");
    // 用一下 <cstddef> 的 std::size_t：既消掉 clangd 的 unused-includes 提示，
    // 也让这个回归测试多覆盖一个英文标准头。
    std::size_t count = v.size();
    if (b.get() > 0 && count == 1) {
        return static_cast<int>(count);
    }
    return 0;
}
