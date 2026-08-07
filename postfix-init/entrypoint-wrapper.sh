#!/bin/sh
# Postfix başlamadan önce:
# 1. header_checks dosyasını MAIL_DISPLAY_NAME env'den oluşturur
# 2. opendkim KeyTable, SigningTable, TrustedHosts dosyalarını oluşturur
# Sonra orijinal boky/postfix entrypoint'ini çalıştırır.

set -e

# ---------------------------------------------------------------------------
# 1. DISPLAY NAME — From header düzeltme
# ---------------------------------------------------------------------------
DISPLAY_NAME="${MAIL_DISPLAY_NAME:-Mail}"
DOMAIN="${DOMAINNAME:-localhost}"

echo "[wrapper] Display name: '${DISPLAY_NAME}' / Domain: '${DOMAIN}'"

sed "s/__DISPLAY_NAME__/${DISPLAY_NAME}/g" \
     /header_checks.template \
    > /etc/postfix/header_checks

echo "[wrapper] /etc/postfix/header_checks oluşturuldu."

# ---------------------------------------------------------------------------
# 2. DKIM — KeyTable, SigningTable, TrustedHosts
# ---------------------------------------------------------------------------
DKIM_KEY_DIR="/etc/opendkim/keys/${DOMAIN}"
DKIM_SELECTOR="${DKIM_SELECTOR:-mail}"

# Anahtar yoksa ve DKIM_AUTOGENERATE=1 ise üret
if [ ! -f "${DKIM_KEY_DIR}/${DKIM_SELECTOR}.private" ]; then
    if [ "${DKIM_AUTOGENERATE:-0}" = "1" ]; then
        echo "[wrapper] DKIM anahtarı bulunamadı, üretiliyor..."
        mkdir -p "${DKIM_KEY_DIR}"
        opendkim-genkey -b 2048 -d "${DOMAIN}" -D "${DKIM_KEY_DIR}" -s "${DKIM_SELECTOR}" -v
        chown -R opendkim:opendkim "${DKIM_KEY_DIR}"
        chmod 600 "${DKIM_KEY_DIR}/${DKIM_SELECTOR}.private"
        echo "[wrapper] DNS'e eklenecek public key:"
        cat "${DKIM_KEY_DIR}/${DKIM_SELECTOR}.txt"
    else
        echo "[wrapper] UYARI: DKIM anahtarı yok: ${DKIM_KEY_DIR}/${DKIM_SELECTOR}.private"
        echo "[wrapper] DKIM_AUTOGENERATE=1 yaparak otomatik üretebilirsin."
    fi
else
    echo "[wrapper] DKIM anahtarı mevcut: ${DKIM_KEY_DIR}/${DKIM_SELECTOR}.private"
    chown opendkim:opendkim "${DKIM_KEY_DIR}/${DKIM_SELECTOR}.private" 2>/dev/null || true
fi


cat > /etc/opendkim/KeyTable << KEYTABLE
${DKIM_SELECTOR}._domainkey.${DOMAIN} ${DOMAIN}:${DKIM_SELECTOR}:${DKIM_KEY_DIR}/${DKIM_SELECTOR}.private
KEYTABLE

cat > /etc/opendkim/SigningTable << SIGNTABLE
*@${DOMAIN} ${DKIM_SELECTOR}._domainkey.${DOMAIN}
SIGNTABLE

cat > /etc/opendkim/TrustedHosts << TRUSTED
127.0.0.1
localhost
${DOMAIN}
mail.${DOMAIN}
172.16.0.0/12
10.0.0.0/8
TRUSTED

echo "[wrapper] opendkim tabloları oluşturuldu: KeyTable, SigningTable, TrustedHosts"


# ---------------------------------------------------------------------------
# 3. Orijinal boky/postfix entrypoint'ini çalıştır
# ---------------------------------------------------------------------------
# Orijinal boky/postfix entrypoint'ini çalıştır
exec /scripts/run.sh "$@"
