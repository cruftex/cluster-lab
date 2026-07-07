# stub to put self signed cert
# TODO: have a CA for testing on the host

PROJECT_NAME=$(basename `pwd`)
CFG=.config
YAML=cluster/platform/traefik/selfsigned-cert.yaml
mkdir -p $CFG
mkdir -p $(dirname $YAML)

openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout $CFG/tls.key \
  -out $CFG/tls.crt \
  -subj "/CN=*.$PROJECT_NAME.test" \
  -addext "subjectAltName=DNS:*.$PROJECT_NAME.test,DNS:$PROJECT_NAME.test"

kubectl -n traefik create secret tls cluster-test-tls \
  --cert=$CFG/tls.crt \
  --key=$CFG/tls.key \
  --dry-run=client -o yaml > $YAML
  
