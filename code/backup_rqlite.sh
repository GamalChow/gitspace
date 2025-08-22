#!/bin/bash

# 日志函数
log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# 备份数据库
backup_database() {
    log_info "开始备份数据库..."
    
    # 切换到工作目录
    cd /opt/mgnt/conf || {
        log_error "无法切换到 /opt/mgnt/conf 目录"
        exit 1
    }

	# 原数据库备份文件重命名
	[ -f dj.backup.sql ] && mv dj.backup.sql dj.backup.sql.old
    
	# 导出数据库
	echo -e "rqlite -u admin:sysadmin << EOF\n.dump dj.backup.sql\nexit docker\nEOF">backup_db	
	log_info "备份数据库文件..."
	docker-compose exec -T rqlite sh -s /usr/bin < backup_db >/dev/null
	if [ $? -ne 0 ]; then
		log_error "数据库导出失败"
		exit 1
	fi
    
    # 从容器中复制备份文件
    docker cp mgnt_rqlite_1:/dj.backup.sql ./dj.backup.sql
    if [ $? -ne 0 ]; then
        log_error "复制备份文件失败"
        exit 1
    fi
    
    # 验证备份文件是否存在
    if [ -f "dj.backup.sql" ]; then
        log_info "备份完成，文件已保存在 /opt/mgnt/conf/dj.backup.sql"
    else
        log_error "备份文件不存在"
        exit 1
    fi
}

# 执行备份
backup_database
