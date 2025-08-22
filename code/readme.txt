执行步骤如下：

前置条件：管理节点到其他节点提前配置好免密。

1. 执行setup_manage_ip.sh修改管理网IP地址
2. 执行backup_rqlite.sh备份数据库
3. 执行update_cluster_ip执行容器和数据库相关的操作
4. 执行setup_private_ip.sh修改存储私网IP地址
5. 执行setup_public_ip.sh修改存储业务网IP地址