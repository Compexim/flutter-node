#!/bin/sh

# SSH kulcs engedély beállítás (kötelező)
chmod 600 /root/.ssh/electo.rsa

# SSH tunnel indítása háttérben
ssh -N -f Electo

# 1-2 mp várakozás, hogy az SSH tunnel felépüljön
sleep 2

# Node.js szerver indítása
node index.js
