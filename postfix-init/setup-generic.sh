#!/bin/sh
# Postfix display name ve sender canonical map oluşturur.
# docker-entrypoint.d/ altında çalışır — Postfix başlamadan önce tetiklenir.
#
# Sonuç:
#   From: root <noreply@hch.tr>   →   From: Hisar <noreply@hch.tr>
#   From: www <printer@hch.tr>    →   From: Hisar <printer@hch.tr>
#
# Env değişkenleri:
#   MAIL_DISPLAY_NAME   → görüntülenecek isim (ör: Hisar)
#   MAIL_DEFAULT_FROM   → adres belirtilmemişse kullanılacak varsayılan adres

set -e

DISPLAY_NAME="${MAIL_DISPLAY_NAME:-Mail}"
DEFAULT_FROM="${MAIL_DEFAULT_FROM:-noreply@localhost}"
DOMAIN="${DOMAINNAME:-localhost}"

echo "[setup-generic] Display name: '${DISPLAY_NAME}'"
echo "[setup-generic] Default from: '${DEFAULT_FROM}'"

# /etc/postfix/generic
# Giden maillerde sistem kullanıcı adlarını (root, www, daemon vb.)
# gerçek adres + display name ile değiştirir.
# Format: <kaynak>   <hedef>
cat > /etc/postfix/generic << GENERIC
# Sistem kullanıcıları → display name ile gerçek adres
root@${DOMAIN}       ${DISPLAY_NAME} <${DEFAULT_FROM}>
root                 ${DISPLAY_NAME} <${DEFAULT_FROM}>
www@${DOMAIN}        ${DISPLAY_NAME} <${DEFAULT_FROM}>
www                  ${DISPLAY_NAME} <${DEFAULT_FROM}>
daemon@${DOMAIN}     ${DISPLAY_NAME} <${DEFAULT_FROM}>
daemon               ${DISPLAY_NAME} <${DEFAULT_FROM}>
GENERIC

# /etc/postfix/sender_canonical
# Envelope sender'ı da düzeltir (bounce adresi için)
cat > /etc/postfix/sender_canonical << CANONICAL
root@${DOMAIN}       ${DEFAULT_FROM}
root                 ${DEFAULT_FROM}
www@${DOMAIN}        ${DEFAULT_FROM}
www                  ${DEFAULT_FROM}
daemon@${DOMAIN}     ${DEFAULT_FROM}
daemon               ${DEFAULT_FROM}
CANONICAL

# lmdb formatına derle
postmap lmdb:/etc/postfix/generic       2>/dev/null || \
postmap hash:/etc/postfix/generic

postmap lmdb:/etc/postfix/sender_canonical  2>/dev/null || \
postmap hash:/etc/postfix/sender_canonical

echo "[setup-generic] Map dosyaları oluşturuldu."