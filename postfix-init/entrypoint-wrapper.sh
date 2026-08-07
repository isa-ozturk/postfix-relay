#!/bin/sh
# Postfix başlamadan önce:
# 1. sender_canonical_maps — sistem kullanıcılarını (root, www, daemon)
#    MAIL_DEFAULT_FROM adresine çevirir. DKIM imzasından önce çalışır.
# 2. opendkim KeyTable, SigningTable, TrustedHosts — her restart'ta yeniden oluşturur.
# Sonra orijinal boky/postfix entrypoint'ini çalıştırır.

set -e

DOMAIN="${DOMAINNAME:-localhost}"
DEFAULT_FROM="${MAIL_DEFAULT_FROM:-noreply@${DOMAIN}}"
DKIM_SELECTOR="${DKIM_SELECTOR:-mail}"
DKIM_KEY_DIR="/etc/opendkim/keys/${DOMAIN}"

echo "[wrapper] Domain: '${DOMAIN}'"
echo "[wrapper] Default from: '${DEFAULT_FROM}'"

# ---------------------------------------------------------------------------
# 1. SENDER CANONICAL — sistem kullanıcılarını gerçek adrese çevir
# root, www, daemon vb. → noreply@domain
# DKIM imzasından ÖNCE envelope'da uygulanır — imzayı bozmaz
# ---------------------------------------------------------------------------
cat > /etc/postfix/sender_canonical << CANONICAL
root@${DOMAIN}      ${DEFAULT_FROM}
root                ${DEFAULT_FROM}
www@${DOMAIN}       ${DEFAULT_FROM}
www                 ${DEFAULT_FROM}
daemon@${DOMAIN}    ${DEFAULT_FROM}
daemon              ${DEFAULT_FROM}
nobody@${DOMAIN}    ${DEFAULT_FROM}
nobody              ${DEFAULT_FROM}
postfix@${DOMAIN}   ${DEFAULT_FROM}
postfix             ${DEFAULT_FROM}
CANONICAL

postmap lmdb:/etc/postfix/sender_canonical 2>/dev/null || \
postmap hash:/etc/postfix/sender_canonical

echo "[wrapper] sender_canonical oluşturuldu → ${DEFAULT_FROM}"

# ---------------------------------------------------------------------------
# 2. DKIM — KeyTable, SigningTable, TrustedHosts
# boky/postfix'in kendi sistemi: anahtar /etc/opendkim/keys/${DOMAIN}.private
# olmalı. Volume'daki anahtarı doğru konuma link'le.
# ---------------------------------------------------------------------------

# Volume'daki anahtarı (keys/domain/mail.private) image'ın beklediği
# konuma (keys/domain.private) sembolik link ile bağla
if [ -f "${DKIM_KEY_DIR}/${DKIM_SELECTOR}.private" ]; then
    if [ ! -f "/etc/opendkim/keys/${DOMAIN}.private" ]; then
        ln -sf "${DKIM_KEY_DIR}/${DKIM_SELECTOR}.private" \
               "/etc/opendkim/keys/${DOMAIN}.private"
        echo "[wrapper] DKIM key symlink: ${DKIM_KEY_DIR}/${DKIM_SELECTOR}.private → /etc/opendkim/keys/${DOMAIN}.private"
    fi
fi

# ---------------------------------------------------------------------------
# 3. Orijinal boky/postfix entrypoint'ini çalıştır
# run.sh içindeki postfix_setup_dkim ALLOWED_SENDER_DOMAINS ile
# KeyTable/SigningTable'ı otomatik oluşturur
# ---------------------------------------------------------------------------
exec /scripts/run.sh "$@"