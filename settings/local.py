"""
本地配置模块，用于从本地配置文件中加载配置
"""

import os
import json5  # 替换原来的json模块

# 配置文件路径
CONFIG_FILE_PATH = os.path.join(os.path.dirname(os.path.dirname(__file__)), "config.json")

# 默认配置
IS_CAPCUT_ENV = True

# 默认域名配置
DRAFT_DOMAIN = "https://www.install-ai-guider.top"

# 默认预览路由
PREVIEW_ROUTER = "/draft/downloader"

# 端口号
PORT = 9000

# 尝试加载本地配置文件
if os.path.exists(CONFIG_FILE_PATH):
    try:
        with open(CONFIG_FILE_PATH, "r", encoding="utf-8") as f:
            # 使用json5.load替代json.load
            local_config = json5.load(f)
            
            # 更新是否是国际版
            if "is_capcut_env" in local_config:
                IS_CAPCUT_ENV = local_config["is_capcut_env"]
            
            # 更新域名配置
            if "draft_domain" in local_config:
                DRAFT_DOMAIN = local_config["draft_domain"]

            # 更新端口号配置
            if "port" in local_config:
                PORT = local_config["port"]

            # 更新预览路由
            if "preview_router" in local_config:
                PREVIEW_ROUTER = local_config["preview_router"]

    except Exception as e:
        # 配置文件加载失败，使用默认配置
        pass
