# 编译作品说明文档（XeLaTeX 至少编译两次）
# 用法: .\compile.ps1

$ErrorActionPreference = "Stop"

$srcDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Push-Location $srcDir

try {
    Write-Host "=== 第 1 次编译 ===" -ForegroundColor Cyan
    & "D:\MiKTeX\miktex\bin\x64\xelatex.exe" -no-pdf "01-作品说明文档Nexus"
    if ($LASTEXITCODE -ne 0) { throw "第一次编译失败" }

    Write-Host "=== 第 2 次编译 ===" -ForegroundColor Cyan
    & "D:\MiKTeX\miktex\bin\x64\xelatex.exe" "01-作品说明文档Nexus"
    if ($LASTEXITCODE -ne 0) { throw "第二次编译失败" }

    Write-Host "=== 第 3 次编译（确保目录/Pageref 正确） ===" -ForegroundColor Cyan
    & "D:\MiKTeX\miktex\bin\x64\xelatex.exe" "01-作品说明文档Nexus"
    if ($LASTEXITCODE -ne 0) { throw "第三次编译失败" }

    Write-Host "`n✅ PDF 生成成功: $srcDir\01-作品说明文档Nexus.pdf" -ForegroundColor Green
}
catch {
    Write-Host "`n❌ 编译失败: $_" -ForegroundColor Red
    exit 1
}
finally {
    Pop-Location
}
