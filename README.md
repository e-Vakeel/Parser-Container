## Let’s say you have both these files in a directory tika_dir. First you need to build your docker container:
```
docker build -t tikapipes tika_dir
```
## start the server in a docker container with your custom config file
```
 docker run -d \
    --name tika_container \
    -v ~/.aws/:/root/.aws:ro \ # Remove this line if credentials provider is set to 'instance'
    -v tika_dir:/config \
    -p 9998:9998 tikapipes:latest \
    -c ./config/tika-config.xml
```
