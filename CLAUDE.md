## 项目介绍
- 本项目是由 Hugo + Blowfish 主题驱动的个人博客
- 使用 Docker Compose 构建和部署，Caddy 负责 HTTPS 和反向代理

## 常用命令
- 本地预览：`docker compose up hugo-dev`
- 访问地址：`http://localhost:1313`

## 目录结构关键说明
- 文章放在 `content/posts/`
- 主题配置在 `config/_default/`（Blowfish 的配置结构）
- Caddy 配置文件：`Caddyfile`

## 注意事项
- Blowfish git submodule 引入, 不要直接修改 `themes/` 下的文件
