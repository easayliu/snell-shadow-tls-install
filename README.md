# snell-shadow-tls-install
Install snell+shadow-tls and disable external direct connection for snell.

Install Shell
```shell
bash <(wget -qO- --no-check-certificate https://raw.githubusercontent.com/easayliu/snell-shadow-tls-install/main/snell-tls-install.sh)
```

Uninstall Shell
```shell
bash <(wget -qO- --no-check-certificate https://raw.githubusercontent.com/easayliu/snell-shadow-tls-install/main/snell-tls-uninstall.sh)
```


Install Only Snell Shell
```shell
bash <(wget -qO- --no-check-certificate https://raw.githubusercontent.com/easayliu/snell-shadow-tls-install/main/snell-install.sh)
```

Install HTTP Proxy (tinyproxy)
```shell
# 用法: bash install_http.sh [端口] [用户名] [密码]，默认 8080 / proxy / 随机密码
bash <(wget -qO- --no-check-certificate https://raw.githubusercontent.com/easayliu/snell-shadow-tls-install/main/install_http.sh)
```

Uninstall HTTP Proxy
```shell
bash <(wget -qO- --no-check-certificate https://raw.githubusercontent.com/easayliu/snell-shadow-tls-install/main/install_http.sh) uninstall
```
