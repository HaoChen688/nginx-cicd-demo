#!/usr/bin/env bash
set -euo pipefail

# 目标部署目录
DEPLOY_DIR="/var/www/nginx-cicd-demo"
STAGING_DIR="/tmp/nginx-cicd-demo-stage"
NGINX_CONF_SRC="${STAGING_DIR}/nginx-cicd-demo.conf"
NGINX_CONF_DST="/etc/nginx/conf.d/nginx-cicd-demo.conf"
BACKUP_ROOT="/var/www/backups"

echo "==> Deploying to ${DEPLOY_DIR}"

# 1) 确保目录存在
sudo mkdir -p "${DEPLOY_DIR}"
sudo mkdir -p "${BACKUP_ROOT}"

# 2) 备份旧版本（保留最近 5 个）
if [ -d "${DEPLOY_DIR}" ] && [ "$(ls -A ${DEPLOY_DIR} 2>/dev/null || true)" ]; then
  BACKUP_DIR="${BACKUP_ROOT}/nginx-cicd-demo-$(date +%Y%m%d%H%M%S)"
  sudo cp -r "${DEPLOY_DIR}" "${BACKUP_DIR}"
  ls -1dt ${BACKUP_ROOT}/nginx-cicd-demo-* 2>/dev/null | tail -n +6 | xargs -r sudo rm -rf
fi

# 3) 同步静态文件
sudo rsync -a --delete "${STAGING_DIR}/public/" "${DEPLOY_DIR}/"

# 4) 权限（Nginx 运行用户通常为 nginx）
if id nginx >/dev/null 2>&1; then
  NGINX_USER="nginx"
else
  NGINX_USER="www-data"
fi
sudo chown -R "${NGINX_USER}:${NGINX_USER}" "${DEPLOY_DIR}"
sudo find "${DEPLOY_DIR}" -type d -exec chmod 755 {} \;
sudo find "${DEPLOY_DIR}" -type f -exec chmod 644 {} \;

# 5) SELinux 上下文（CentOS 默认开启）
if command -v chcon >/dev/null 2>&1; then
  sudo chcon -R -t httpd_sys_content_t "${DEPLOY_DIR}" || true
fi

# 6) 安装/更新 Nginx 站点配置（仅首次放置，不覆盖本地自定义）
if [ -f "${NGINX_CONF_SRC}" ]; then
  if [ ! -f "${NGINX_CONF_DST}" ]; then
    echo "==> Installing nginx site config"
    sudo cp "${NGINX_CONF_SRC}" "${NGINX_CONF_DST}"
  else
    # 有变化则更新（首次生成的也是同一份）
    if ! sudo cmp -s "${NGINX_CONF_SRC}" "${NGINX_CONF_DST}"; then
      echo "==> Updating nginx site config"
      sudo cp "${NGINX_CONF_SRC}" "${NGINX_CONF_DST}"
    fi
  fi
fi

# 7) 校验 & 重载 Nginx
echo "==> Validating nginx config"
sudo nginx -t
echo "==> Reloading nginx"
sudo systemctl reload nginx

echo "==> Deployment finished"