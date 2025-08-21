#!/bin/bash

HOSTS=("node01" "node02" "node03")
MANAGE=(`cat /root/foss-deploy/deploy_tool.yaml | grep -E "^    CtrlIp" |awk '{print $2}'`)

clean(){
     for i in ${HOSTS[@]} ;do
	ssh $i "supervisorctl stop all"
     done

     cd /data/foss3/work
     ./md_tool clear-all
     docker exec -it foss_mgnt sh -c "
     cd foss-backend;
     python manage.py loaddata user/fixtures/initial_data.yaml;
     sleep 5;
     exit; "

    for i in ${HOSTS[@]} ;do
        ssh $i "supervisorctl start all"
    done
}

solve_500(){
    for i in ${MANAGE[@]};do
        ssh $i "ps -ef | grep s3s_api" | grep -Ev "bash|grep"
        if [[ $? -eq 0 ]];then
                  sed -ri "34s/([0-9]{1,3}\.){3}[0-9]{1,3}/${i}/" /opt/foss_mgnt/conf/settings.py
           docker  restart foss_mgnt
           break
        fi
    done      
}

echo "*************************************************************"
echo "-----------> 本脚本适用于Taocloud FOSS<------------"
echo "*************************************************************"
echo
echo "-> 1.清空配置文件(清理完成后需要手动清理每个数据磁盘的元数据信息）"
echo "-> 2.解决web的500报错"
echo "-> 3.退出。"
echo -e " 请选择一个操作：\t\c"
read input
case $input in
	1)
		echo "->您选择了修改管理网IP地址"
		clean
		;;
	2)
		echo "->您选择了修改存储网IP地址"
		solve_500
		;;
	3)
		echo "退出"
		break
		;;
	*) echo "无效的选项" ;;
esac
