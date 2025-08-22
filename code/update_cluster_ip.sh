#!/bin/bash

input_record="/tmp/.ip.record.manage_ip"

# 切换到工作目录
cd /opt/mgnt/conf || {
    echo "[ERROR] 无法切换到 /opt/mgnt/conf 目录"
    exit 1
}

# 日志函数
log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# 检查工作环境
check_environment() {
    log_info "检查工作环境..."
    
    # 检查必要目录
    for dir in "/opt/mgnt/conf" "/opt/mgnt/data/rqlite"; do
        if [ ! -d "$dir" ]; then
            log_error "目录不存在: $dir"
            exit 1
        fi
    done
    
    # 检查docker和docker-compose
    if ! command -v docker >/dev/null 2>&1; then
        log_error "docker未安装"
        exit 1
    fi
    
    if ! command -v docker-compose >/dev/null 2>&1; then
        log_error "docker-compose未安装"
        exit 1
    fi
    
    log_info "环境检查完成"
}

# 获取IP地址相关信息
parse_config_file() {
	log_info "获取IP配置信息..."

	if [ ! -f $input_record ]; then
		log_error "IP配置文件$input_record不存在，请先执行setup_manage_ip操作"
		exit 1
	fi

	node_count=`sed -n '1p' $input_record|awk -F':' '{print $2}'`
	old_vip=`sed -n '2p' $input_record|awk -F':' '{print $2}'`
	new_vip=`sed -n '2p' $input_record|awk -F':' '{print $3}'`
	new_mask=`sed -n '2p' $input_record|awk -F':' '{print $4}'`
	new_gateway=`sed -n '3p' $input_record|awk -F':' '{print $2}'`

	log_info "节点数：$node_count"
	log_info "原VIP：$old_vip，更改后VIP：$new_vip，子网掩码：$new_mask"

	IFS=':'
	read -ra old_ip <<< `sed -n '4p' $input_record`
	read -ra new_ip <<< `sed -n '5p' $input_record`

	for i in "${!old_ip[@]}"; do
		let i++
		if [ ${old_ip[$i]} ]; then
			log_info "节点$i:原管理网地址【${old_ip[$i]}】-> 新地址【${new_ip[$i]}】"
		fi
	done

	IFS=''

	read -p "->确认请输入yes：" input
	if [[ $input != "yes" ]];then
	     log_error "IP地址未变更，退出..."
	fi
}

# 在远程节点执行命令
execute_remote_command() {
    local ip=$1
    local command=$2
    log_info "在节点 $ip 上执行命令..."
    ssh -o StrictHostKeyChecking=no "root@$ip" "$command"
    if [ $? -ne 0 ]; then
        log_error "在节点 $ip 上执行命令失败"
        return 1
    fi
}

# 更新本地配置文件
update_local_configs() {
    log_info "更新本地配置文件..."
    
    # 更新node.yaml和push-install.yaml
    sed -i "s/${old_ip[1]}/${new_ip[1]}/g" node.yaml
    sed -i "s/${old_ip[1]}/${new_ip[1]}/g" push-install.yaml

    # 更新rqlite-entrypoint.sh
    sed -i "s/${old_ip[1]}/${new_ip[1]}/g" rqlite-entrypoint.sh
    if [ "$node_count" -ge 2 ]; then
        sed -i "s/${old_ip[2]}/${new_ip[2]}/g" rqlite-entrypoint.sh
    fi
    if [ "$node_count" -ge 3 ]; then
        sed -i "s/${old_ip[3]}/${new_ip[3]}/g" rqlite-entrypoint.sh
    fi

    # 更新network_keep.sh（如果存在）
    if [ -f "/etc/keepalived/sh/network_keep.sh" ]; then
        log_info "更新network_keep.sh..."
        sed -i "s/${old_ip[1]}/${new_ip[1]}/g" /etc/keepalived/sh/network_keep.sh
    fi

    #sed -i "s/$old_vip/$new_vip/g" /etc/keepalived/keepalived.conf
    sed -i "s|$old_vip/[0-9][0-9]|$new_vip/$new_mask|g" /etc/keepalived/keepalived.conf

    # 更新env.prod
    sed -i "s/$old_vip/$new_vip/g" env.prod

    # 更新config.json中的base64编码
    local new_base64=$(echo "http://$new_vip" | base64 | tr -d '\n')
    sed -i "s|\"TC_YYDS\":\"[^\"]*\"|\"TC_YYDS\":\"$new_base64\"|" config.json
    
    log_info "本地配置文件更新完成"
}

# 更新远程节点配置
update_remote_configs() {
    local target_ip=$1
    log_info "更新节点 $target_ip 的配置..."

    local commands="cd /opt/mgnt/conf && \
        sed -i 's/${old_ip[1]}/${new_ip[1]}/g' node.yaml && \
        sed -i 's/${old_ip[1]}/${new_ip[1]}/g' push-install.yaml && \
        sed -i 's/${old_ip[1]}/${new_ip[1]}/g' rqlite-entrypoint.sh"

    if [ "$node_count" -ge 2 ]; then
        commands="$commands && sed -i 's/${old_ip[2]}/${new_ip[2]}/g' rqlite-entrypoint.sh"
    fi

    if [ "$node_count" -gt 3 ]; then
        commands="$commands && sed -i 's/${old_ip[3]}/${new_ip[3]}/g' rqlite-entrypoint.sh"
    fi

    commands="$commands && sed -i 's/$old_vip/$new_vip/g' env.prod"

    # 更新keepalived.conf（如果存在）
    commands="$commands && sed -i 's|$old_vip/[0-9][0-9]|$new_vip/$new_mask|g' /etc/keepalived/keepalived.conf"

    execute_remote_command "$target_ip" "$commands"
}

# 重建rqlite集群
rebuild_rqlite_cluster() {
    log_info "开始重建rqlite集群..."
    

    # 1. 停止所有节点的服务
    log_info "停止所有节点的服务..."
    cd /opt/mgnt/conf && docker-compose down
    if [ "$node_count" -ge 2 ]; then
        execute_remote_command "${new_ip[2]}" "cd /opt/mgnt/conf && docker-compose down"
    fi
    if [ "$node_count" -ge 3 ]; then
        execute_remote_command "${new_ip[3]}" "cd /opt/mgnt/conf && docker-compose down"
    fi
    
    # 等待所有服务完全停止
    sleep 5
    
    # 2. 清理所有节点的数据
    log_info "清理所有节点的数据..."
    # 清理本地数据
    rm -rf /opt/mgnt/data/rqlite/*
    mkdir -p /opt/mgnt/data/rqlite
    chmod -R 755 /opt/mgnt/data/rqlite
    
    # 清理其他节点数据
    if [ "$node_count" -ge 2 ]; then
        execute_remote_command "${new_ip[2]}" "rm -rf /opt/mgnt/data/rqlite/* && mkdir -p /opt/mgnt/data/rqlite && chmod -R 755 /opt/mgnt/data/rqlite"
    fi
    if [ "$node_count" -ge 3 ]; then
        execute_remote_command "${new_ip[3]}" "rm -rf /opt/mgnt/data/rqlite/* && mkdir -p /opt/mgnt/data/rqlite && chmod -R 755 /opt/mgnt/data/rqlite"
    fi
    
    # 3. 启动所有节点的服务
    log_info "启动所有节点的服务..."
    # 先启动主节点
    cd /opt/mgnt/conf && docker-compose up -d
    sleep 5
    
    # 然后启动其他节点
    if [ "$node_count" -ge 2 ]; then
        execute_remote_command "${new_ip[2]}" "cd /opt/mgnt/conf && docker-compose up -d"
    fi
    if [ "$node_count" -ge 3 ]; then
        execute_remote_command "${new_ip[3]}" "cd /opt/mgnt/conf && docker-compose up -d"
    fi
    
    # 等待服务完全启动
    log_info "等待服务启动..."
    sleep 10
    
    log_info "rqlite集群重建完成"
}

# 恢复数据库
restore_database() {
    log_info "恢复数据库..."
    
    # 确保在正确的目录
    cd /opt/mgnt/conf || {
        log_error "无法切换到 /opt/mgnt/conf 目录"
        exit 1
    }
    
    # 复制备份文件到容器
    docker cp dj.backup.sql mgnt_rqlite_1:/
    if [ $? -ne 0 ]; then
        log_error "复制备份文件失败"
        exit 1
    fi

    # 执行恢复操作
    log_info "数据库恢复..."
    echo -e "rqlite -u admin:sysadmin << EOF\n.restore dj.backup.sql\nexit docker\nEOF">restore_db

    docker-compose exec -T rqlite sh -s /usr/bin < restore_db
    if [ $? -ne 0 ]; then
        log_error "数据恢复失败"
        exit 1
    fi
   
    # 更新数据库中管理网IP
	for i in "${!old_ip[@]}"; do
		let i++
		if [ ${old_ip[$i]} ]; then
			echo -e "rqlite -u admin:sysadmin << EOF\nupdate hardware_device set manage_ip='${new_ip[$i]}' where manage_ip='${old_ip[$i]}'\nexit docker\nEOF">update_ipaddress
			docker-compose exec -T rqlite sh -s /usr/bin < update_ipaddress >/dev/null
			if [ $? -eq 0 ]; then
				log_info "数据库更新地址：${new_ip[$i]}完成"
			else
				log_error "数据库更新地址：${new_ip[$i]}失败"
				exit 1
			fi
		fi
	done
}

# 主函数
main() {
    log_info "开始IP变更流程..."
    
    # 1. 检查环境
    check_environment
    
    # 2. 确认数据库文件是否已经备份
    if [ ! -f "/opt/mgnt/conf/dj.backup.sql" ]; then
	log_error "数据库文件未备份，请先备份数据库"
	exit
    fi
    # 3. 获取用户输入
    #get_user_input
    parse_config_file
    
    # 4. 更新本地配置
    update_local_configs
    
    # 5. 更新其他节点配置
    if [ "$node_count" -ge 2 ]; then
        update_remote_configs "${new_ip[2]}"
    fi

    if [ "$node_count" -ge 3 ]; then
        update_remote_configs "${new_ip[3]}"
    fi
    
    # 6. 重启keepalived（如果存在）
    if [ -f "/etc/keepalived/keepalived.conf" ]; then
        systemctl restart keepalived
        if [ "$node_count" -ge 2 ]; then
            execute_remote_command "${new_ip[2]}" "systemctl restart keepalived"
        fi
        if [ "$node_count" -ge 3 ]; then
            execute_remote_command "${new_ip[3]}" "systemctl restart keepalived"
        fi
    fi
    
    # 7. 重建rqlite集群
    rebuild_rqlite_cluster
    
    # 8. 恢复数据
    restore_database
    
    log_info "IP变更流程完成"
}

# 执行主函数
main
