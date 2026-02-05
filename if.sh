#!/bin/bash


USER=`awk -F: '{print $1}' /etc/passwd`

get_user(){
	
	for i in ${USER[@]};do
		echo -e "$i\t"
	done


}

get_uptime_info(){
	local total_day=`uptime|awk '{print $3}' `
	local status=`uptime|awk '{print $2}' `
	local min_cpu_avgload=`uptime|awk -F "[, ]" '{print $(NF-4)}' `

	if [[ ${total_day} -gt 10 ]];then
		echo -ne "the host which runs for $total_day is more than 10days\n"
	else
		echo -ne "the host which runs for $total_day is less than 10days\n"
	fi

	if [[ ${status} =~ up ]];then
		echo -ne "the host is working\n"
	else
		echo -ne "the host is not working\n"
	fi

	if [[ `echo "${min_cpu_avgload} > 0.03"|bc` -eq 1 ]];then
		echo -ne "该1min的cpu平均负载为$min_cpu_avgload,大于0.03\n"
	else
		echo -ne "该1min的cpu平均负载为$min_cpu_avgload,小于0.03\n"
	fi
}

main(){
	
	get_user
	get_uptime_info
}

main
