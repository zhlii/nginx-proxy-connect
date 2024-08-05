## nginx-proxy-connect

nginx做正向代理时，由于本身不能部署被代理的网站的证书，与客户端之间不能用ssl协议通讯，因此需要通过http协议中的CONNECT请求打通和被代理网站的连接。客户端到nginx走http协议，nginx到被代理网站走https协议

nginx原生是不支持CONNECT请求的，需要安装一个扩展插件，即[ngx_http_proxy_connect_module](https://github.com/chobits/ngx_http_proxy_connect_module)

```nginx.conf
server {
    # 代理端口
    listen          8080;
    server_name     localhost;
    
    # 解析被代理网站域名的dns服务器，根据实际情况自行配置
    resolver  114.114.114.114;
    
    # 开启proxy connect功能
    proxy_connect;
    
    # 设置允许代理的目标端口为443,即https的默认端口
    proxy_connect_allow 443 80;

    location / { 
        # 正向代理配置，根据请求地址自动解析出目标网站地址并进行代理
        proxy_pass $scheme://$host$request_uri;
        
        # 发送到被代理网站的请求需要添加host头
        proxy_set_header Host $http_host;
    
        proxy_buffers 256 4k; 
        proxy_max_temp_file_size 0;
        proxy_connect_timeout 30; 
    }
}
```