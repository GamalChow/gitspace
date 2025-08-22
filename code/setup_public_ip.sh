#!/bin/bash

input_record="/tmp/.ip.record.public_ip"

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

# 保存ip地址配置,供出错时参考
store_ip_info() {
	echo -e "count:$node_count\nvip:$old_vip:$new_vip:$new_mask">$input_record
	
	for i in "${!old_ip[@]}"; do
		if [ ${old_ip[$i]} ]; then
			echo "节点$(expr $i + 1):${old_ip[$i]}:${new_ip[$i]}">>$input_record
		fi
	done
}

# 获取用户输入
get_user_input() {
    log_info "开始获取用户输入..."
    read -p "请输入集群节点数量(1/2/3/4): " node_count
    if [[ ! $node_count =~ ^[1-4]$ ]]; then
        log_error "节点数量必须是1、2、3或者4"
        exit 1
    fi

    read -p "请输入旧的VIP地址: " old_vip
    read -p "请输入新的VIP地址: " new_vip
    read -p "请输入新的VIP子网掩码位数：" new_mask
    read -p "请输入新的VIP默认网关：" new_gateway

    read -p "请输入第一个节点(当前主节点)的旧IP: " old_ip1
    read -p "请输入第一个节点(当前主节点)的新IP: " new_ip1

    if [ "$node_count" -ge 2 ]; then
        read -p "请输入第二个节点的旧IP: " old_ip2
        read -p "请输入第二个节点的新IP: " new_ip2
    fi

    if [ "$node_count" -ge 3 ]; then
        read -p "请输入第三个节点的旧IP: " old_ip3
        read -p "请输入第三个节点的新IP: " new_ip3
    fi

    if [ "$node_count" -ge 4 ]; then
        read -p "请输入第四个节点的旧IP: " old_ip4
        read -p "请输入第四个节点的新IP: " new_ip4
    fi

    # 验证IP格式
    local ip_regex="^([0-9]{1,3}\.){3}[0-9]{1,3}$"
    for ip in "$old_vip" "$new_vip" "$old_ip1" "$new_ip1" "$old_ip2" "$new_ip2" "$old_ip3" "$new_ip3" "$old_ip4" "$new_ip4"; do
        if [ ! -z "$ip" ] && [[ ! $ip =~ $ip_regex ]]; then
            log_error "无效的IP地址格式: $ip"
            exit 1
        fi
    done
}

# 测试网络是否能ping通
ping_ip_test() {
        local target_ip=$1
        if ping -c 1 -w 1 $target_ip >/dev/null; then
                log_info "IP地址：$target_ip 在线"
        else
                log_error "IP地址：$target_ip 离线，请先检查网络."
        fi
}

# 检查网络，确认IP地址信息
print_info() {

	old_ip=("$old_ip1" "$old_ip2" "$old_ip3" "$old_ip4")
	new_ip=("$new_ip1" "$new_ip2" "$new_ip3" "$new_ip4")

	# 打印确认信息
	for i in "${!old_ip[@]}"; do
		if [ ${old_ip[$i]} ]; then
			log_info "节点$i原IP地址：${old_ip[$i]}，修改为： ${new_ip[$i]}"
		fi
	done

	# 测试网络是否能ping通
	for i in "${!old_ip[@]}"; do
		if [ ${old_ip[$i]} ]; then
			ping_ip_test ${old_ip[$i]}
		fi
	done
	
	# 请用户确认
     	read -p "->确认请输入yes：" input
     	if [[ $input != "yes" ]];then
		log_error "IP地址未变更，退出..."
	else
		# 存储用户输入的IP信息，供出错时查询
		store_ip_info
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

# 设置远程节点ip地址
setup_remote_ipaddr() {
	log_info "开始设置远程ip地址..."

	for i in "${!old_ip[@]}"; do
		if [ ${old_ip[$i+1]} ]; then
			local ip_info=`execute_remote_command "${old_ip[$i+1]}" "ip addr show|grep ${old_ip[$i+1]}"`
			local ip_2nic=`echo $ip_info|awk '{print $NF}'`

                        log_info "正在修改IP地址:${old_ip[$i+1]} --> ${new_ip[$i+1]}, 网口名：$ip_2nic"
			execute_remote_command "${old_ip[$i+1]}" "nmcli connection modify $ip_2nic ipv4.method manual ipv4.addresses ${new_ip[$i+1]}/$new_mask"
			timeout 5 ssh -o StrictHostKeyChecking=no root@"${old_ip[$i+1]}" "nmcli connection down $ip_2nic && nmcli connection up $ip_2nic"
                fi
        done
}

# 设置本机IP地址
setup_locale_ipaddr(){
	log_info "开始设置本机ip地址..."

	local ipaddr=`execute_remote_command "$old_ip1" "ip addr show|grep $old_ip1"`
	local nicnme=`echo $ipaddr|awk '{print $NF}'`

	log_info "正在修改IP地址：$old_ip1 -> $new_ip1, 网口名：$nicnme"
	execute_remote_command "$old_ip1" "nmcli connection modify $nicnme ipv4.method manual ipv4.addresses $new_ip1/$new_mask"
	timeout 5 ssh -o StrictHostKeyChecking=no root@"$old_ip1" "nmcli connection down $nicnme && nmcli connection up $nicnme"
}

# 更新配置文件public_addresses
update_public_addresses() {
	log_info "更新配置文件：public_address"

	for i in "${!old_ip[@]}"; do
		if [ ${old_ip[$i]} ];then
			if [ ${old_ip[$i]} ]; then
				local cmd="sed -i 's|$old_vip/[0-9][0-9]|$new_vip/$new_mask|g' /etc/ctdb/public_addresses"
				execute_remote_command "${old_ip[$i]}" "$cmd"
			fi
		fi
        done

}

# 重启ctdb服务更新nodes配置
restart_ha_service() {
	log_info "正在重启高可用（HA）服务..."
	
	for i in "${!new_ip[@]}"; do
		if [ ${new_ip[$i]} ]; then
			local ipaddr=`execute_remote_command "${new_ip[$i]}" "ip addr show|grep ${new_ip[$i]}|awk '{print $NF}'"`
			local ip2nic=`echo $ipaddr|awk '{print $NF}'`
			local cmd="systemctl stop ctdb &&ifdown $ip2nic && ifup $ip2nic && systemctl start ctdb"
			execute_remote_command "${new_ip[$i]}" "$cmd"
		fi
	done
}

main() {
    	
	log_info "这里修改存储业务网IP地址"
	
	# 1.检查基础环境
	check_environment

	# 2.获取用户输入的IP地址
	get_user_input

	# 3.打印输入的IP信息，并请用户确认
	print_info

	# 4.更新配置文件/etc/ctdb/public_addresses
	update_public_addresses

	# 5.更新数据库中private_ip
	# update_database

	# 6.设置远端主机私网地址
	setup_remote_ipaddr

	# 7.设置本机私网地址
	setup_locale_ipaddr

	# 8.重启glusterd服务、ctdb服务
	restart_ha_service
}

main
