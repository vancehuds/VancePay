# 贡献指南

语言：[中文](CONTRIBUTING.md) | [English](CONTRIBUTING.en.md)

感谢你帮助改进 VancePay。

## 开发

本资源会由 FiveM/Qbox 直接加载，没有 bundler 或编译步骤。

提交 Pull Request 前，请运行以下任意一种静态检查：

```bash
./scripts/check.sh
```

```powershell
.\scripts\check.ps1
```

新增 Lua 或浏览器 JavaScript 文件时，需要同时登记到 `fxmanifest.lua` 和检查脚本中。

## Pull Request

- 保持改动聚焦，并说明玩家/管理员可感知的行为变化。
- 明确标注 SQL 或配置变更。
- NUI 和 `lb-phone` UI 变更请附截图或录屏。
- 不要提交密钥、服务器专属 convar、数据库 dump 或本地运行文件。

## 许可证

提交贡献即表示你同意该贡献以 `AGPL-3.0-or-later` 授权。
