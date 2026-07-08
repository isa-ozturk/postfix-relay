#!/bin/sh
# MAIL_DISPLAY_NAME env'den header_checks dosyasını oluştur
# Sonra orijinal boky/postfix entrypoint'ini çağır

DISPLAY_NAME="${MAIL_DISPLAY_NAME:-Mail}"

echo "[entrypoint-wrapper] Display name: '${DISPLAY_NAME}'"

# Template'den gerçek dosyayı üret
sed "s/__DISPLAY_NAME__/${DISPLAY_NAME}/g" \
    /header_checks.template \
    > /etc/postfix/header_checks

echo "[entrypoint-wrapper] /etc/postfix/header_checks oluşturuldu:"
cat /etc/postfix/header_checks

# Orijinal boky/postfix entrypoint'ini çalıştır
exec /scripts/run.sh "$@"
