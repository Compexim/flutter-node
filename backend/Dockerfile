FROM node:18

# Alap mappa
WORKDIR /app

# Függőségek
COPY package*.json ./
RUN npm install

# Fájlok másolása
COPY . .

# SSH mappa
RUN mkdir -p /root/.ssh
COPY electo.rsa /root/.ssh/electo.rsa
COPY config/config /root/.ssh/config

# SSH kliens telepítés
RUN apt-get update && apt-get install -y openssh-client

# Futtatási jogok
RUN chmod 600 /root/.ssh/electo.rsa

# Port
EXPOSE 3000

# Indító script
CMD ["sh", "./start.sh"]
