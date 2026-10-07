# 由《Chinese++ 教学教程》的 Markdown 生成 Word 文档（.docx）。
#
# 为什么要 .docx：Markdown 适合在仓库里读，但教学材料常要发给老师/学生、要打印、
# 要在 Word 里批注 —— 所以额外产出一份 Word 文档。
#
# 【单一真相】docx 由 教程\Chinese++-教学教程.md 生成，不另写一份正文：
#   教程模板.md --(make_tutorial_cpp.ps1)--> 教学教程.md --(本脚本)--> 教学教程.docx
# 于是「例子改了 → 教程重生成 → docx 重生成」是一条链，谁都不会各说各话。
#
# 用法：
#   pwsh -File tools\make_tutorial_docx.ps1          # 生成
#   pwsh -File tools\make_tutorial_docx.ps1 -Check   # 只核对 docx 是否与 md 同步（第 28 道守卫用）
#
# 为什么能 -Check：本脚本把 docx 里的时间戳与 zip 条目时间全部归一化成固定值，
# 所以同样的 md 一定生成逐字节相同的 docx —— 直接比哈希就够了。

param(
    [string]$Pandoc = 'E:\anaconda3\Library\bin\pandoc.exe',
    [switch]$Check
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$md = Join-Path $root '教程\Chinese++-教学教程.md'
$out = Join-Path $root '教程\Chinese++-教学教程.docx'

if (-not (Test-Path $md)) { throw "找不到教程正文：$md（先跑 tools\make_tutorial_cpp.ps1）" }
if (-not (Test-Path $Pandoc)) { throw "找不到 pandoc：$Pandoc" }
Add-Type -AssemblyName System.IO.Compression.FileSystem

# 把 pandoc 的输出重写成【确定性】docx：固定时间戳 + 固定 zip 条目时间
function Write-DeterministicDocx([string]$srcPath, [string]$dstPath) {
    $fixed = [datetimeoffset]::new(1980, 1, 1, 0, 0, 0, [timespan]::Zero)
    $tmp = "$dstPath.tmp"
    if (Test-Path $tmp) { Remove-Item $tmp -Force }
    $src = [System.IO.Compression.ZipFile]::OpenRead($srcPath)
    try {
        $dst = [System.IO.Compression.ZipFile]::Open($tmp, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($e in $src.Entries) {
                $ms = New-Object System.IO.MemoryStream
                $s = $e.Open()
                $s.CopyTo($ms)
                $s.Dispose()
                $bytes = $ms.ToArray()
                $ms.Dispose()

                if ($e.FullName -eq 'docProps/core.xml') {
                    $xml = [System.Text.Encoding]::UTF8.GetString($bytes)
                    $xml = [regex]::Replace($xml, '<dcterms:created[^>]*>[^<]*</dcterms:created>',
                        '<dcterms:created xsi:type="dcterms:W3CDTF">1980-01-01T00:00:00Z</dcterms:created>')
                    $xml = [regex]::Replace($xml, '<dcterms:modified[^>]*>[^<]*</dcterms:modified>',
                        '<dcterms:modified xsi:type="dcterms:W3CDTF">1980-01-01T00:00:00Z</dcterms:modified>')
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes($xml)
                }

                $ne = $dst.CreateEntry($e.FullName, [System.IO.Compression.CompressionLevel]::Optimal)
                $ne.LastWriteTime = $fixed
                $os = $ne.Open()
                $os.Write($bytes, 0, $bytes.Length)
                $os.Dispose()
            }
        } finally { $dst.Dispose() }
    } finally { $src.Dispose() }
    Move-Item $tmp $dstPath -Force
}

function New-Docx([string]$dstPath) {
    $raw = "$dstPath.raw"
    if (Test-Path $raw) { Remove-Item $raw -Force }
    # --toc：教学文档有目录才好用；gfm：按 GitHub 风格解析（表格/围栏代码块）
    & $Pandoc $md -o $raw --from gfm --to docx --toc --toc-depth=2
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $raw)) { throw "pandoc 生成失败（退出码 $LASTEXITCODE）" }
    Write-DeterministicDocx $raw $dstPath
    Remove-Item $raw -Force
}

if ($Check) {
    if (-not (Test-Path $out)) { throw "缺少 $out，请先运行 tools\make_tutorial_docx.ps1" }
    $probe = Join-Path ([System.IO.Path]::GetTempPath()) ("zhcpp-docx-" + [guid]::NewGuid().ToString('N') + ".docx")
    try {
        New-Docx $probe
        $h1 = (Get-FileHash $probe -Algorithm SHA256).Hash
        $h2 = (Get-FileHash $out -Algorithm SHA256).Hash
        if ($h1 -ne $h2) {
            throw ("docx 与教程正文不同步：$out`n" +
                   "  盘上 {0}，按当前 md 重新生成会是 {1}。`n" +
                   "  请运行 tools\make_tutorial_docx.ps1 并提交结果。" -f $h2.Substring(0, 16), $h1.Substring(0, 16))
        }
        Write-Host ("docx 与教程正文同步（SHA256 {0}…）：{1}" -f $h2.Substring(0, 16), $out)
    } finally { if (Test-Path $probe) { Remove-Item $probe -Force } }
    exit 0
}

New-Docx $out
$fi = Get-Item $out
Write-Host ("已生成 {0}（{1} KB，SHA256 {2}…）" -f $out, [math]::Round($fi.Length / 1KB, 1), (Get-FileHash $out -Algorithm SHA256).Hash.Substring(0, 16))
