# Server Scripts Collection

这是一个服务器常用脚本集合，用于简化各种服务器软件的安装和配置过程。

## Docker 一键安装

一行命令安装 Docker（需要 root 权限）：

```bash
curl -fsSL https://raw.githubusercontent.com/fupengl/sh/main/install_docker.sh | bash
```

如果提示权限不足，请先切换到 root 用户：

```bash
sudo -i
```

### 注意事项

- 生产环境使用前建议先在测试环境验证

### 问题反馈

如果在使用过程中遇到任何问题，欢迎提交 Issue。

### 贡献指南

欢迎提交 Pull Request 来改进脚本或添加新的功能。

### 许可证

[MIT License](LICENSE) 