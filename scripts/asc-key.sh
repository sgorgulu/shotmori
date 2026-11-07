# App Store Connect API anahtarı (Admin; bulut imzalama için gerekli): ~/.appstoreconnect/private_keys/AuthKey_<ID>.p8
# + ~/.appstoreconnect/issuer_id. Takımın ortak anahtarı (dosyalar repo dışında, yalnız okunur).
# Kaynak olarak kullanılır: source scripts/asc-key.sh → KEYFILE, KEYID, ISSUER, AUTH=(…)
KEYFILE=$(ls ~/.appstoreconnect/private_keys/AuthKey_*.p8 2>/dev/null | head -1)
[ -n "$KEYFILE" ] && [ -f ~/.appstoreconnect/issuer_id ] || { echo "EKSİK: ~/.appstoreconnect/private_keys/AuthKey_*.p8 ve ~/.appstoreconnect/issuer_id (App Store Connect › Users and Access › Integrations › Admin anahtarı)" >&2; exit 2; }
KEYID=$(basename "$KEYFILE" .p8 | sed 's/AuthKey_//')
ISSUER=$(cat ~/.appstoreconnect/issuer_id)
AUTH=(-allowProvisioningUpdates -authenticationKeyPath "$KEYFILE" -authenticationKeyID "$KEYID" -authenticationKeyIssuerID "$ISSUER")
