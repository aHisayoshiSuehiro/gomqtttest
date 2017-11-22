docker stop mosquitto-ssl
docker run -d --rm -t -p 8883:8883 --name mosquitto-ssl -v `pwd`/immigration/:/mosquitto/config/ -v /dev/log:/dev/log eclipse-mosquitto
