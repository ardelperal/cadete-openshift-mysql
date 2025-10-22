param(
  [ValidateSet("dev","test")]
  [string]$Env = "test"
)

# ===== Config por entorno =====
if ($Env -eq "dev") {
  $NS           = "wcdy-inte-frt"
  $ROUTE        = "cadete3"
  # Host en spec: FQDN del router (Infra lo ha pedido así)
  $HOST_SPEC    = "cadete-wcdy-inte-frt.fi.ocgc4pgpre01.serv.dev.dc.es.telefonica"
  # VIP y FQDN del router para pruebas
  $VIP_ROUTER   = "10.64.217.246"
  $ROUTER_FQDN  = "cadete-wcdy-inte-frt.fi.ocgc4pgpre01.serv.dev.dc.es.telefonica"
  # Whitelist de los Access Gateway
  $AG_IPS       = "10.159.14.245/32"
  # Para curl: en dev Host==router FQDN, no hace falta -H Host
  $NEEDS_HOST_H = $false
  $HOST_HEADER  = $HOST_SPEC
}
else {
  $NS           = "wcdy-cert-frt"
  $ROUTE        = "cadete3"
  # Host en spec: host de aplicación (AG preserva Host)
  $HOST_SPEC    = "cadete.test.es.telefonica"
  # VIP y FQDN del router para pruebas
  $VIP_ROUTER   = "10.64.217.247"
  $ROUTER_FQDN  = "cadete-wcdy-cert-frt.fi.ocgc4pgpre01.serv.test.dc.es.telefonica"
  # Whitelist de los Access Gateway
  $AG_IPS       = "10.159.14.244/32,10.159.14.245/32"
  # Para curl: en test hay que enviar Host de la app
  $NEEDS_HOST_H = $true
  $HOST_HEADER  = $HOST_SPEC
}

Write-Host "Entorno: $Env  Namespace: $NS  Route: $ROUTE" -ForegroundColor Cyan

# ===== 1) BACKUP =====
$ts = Get-Date -Format "yyyyMMdd-HHmmss"
$backup = "route-$ROUTE-$NS-$ts.yaml"
oc.exe -n $NS get route $ROUTE -o yaml | Set-Content -Encoding utf8 $backup
Write-Host "Backup guardado: $backup"

# ===== 2) PATCH: host + TLS edge + redirect + backend 8080 =====
$json = ('{"spec":{"host":"'+$HOST_SPEC+'","port":{"targetPort":8080},"tls":{"termination":"edge","insecureEdgeTerminationPolicy":"Redirect"}}}')
oc.exe -n $NS patch route $ROUTE -p $json | Out-Null

# ===== 3) ANOTACIONES (metadata.annotations) =====
oc.exe -n $NS annotate route $ROUTE `
  ("haproxy.router.openshift.io/ip_whitelist="+$AG_IPS) `
  "haproxy.router.openshift.io/disable_cookies=true" `
  "haproxy.router.openshift.io/timeout=80s" `
  "haproxy.router.openshift.io/hsts_header=max-age=31536000; includeSubDomains; preload" `
  --overwrite | Out-Null

# ===== 4) VERIFICACIONES =====
oc.exe -n $NS get route $ROUTE -o wide
Write-Host "`nAnotaciones actuales:"
oc.exe -n $NS get route $ROUTE -o jsonpath='{.metadata.annotations}{"`n"}'
Write-Host "`nRouters que admiten la Route:"
oc.exe -n $NS get route $ROUTE -o jsonpath='{range .status.ingress[*]}{@.routerName}{" : "}{@.conditions[?(@.type=="Admitted")].status}{"`n"}{end}'

# ===== 5) TESTS tipo Access Gateway =====
Write-Host "`nPruebas curl (simulando AG):" -ForegroundColor Yellow
# 5.1 Conexión TLS al VIP del router
curl.exe -kI --resolve "$($ROUTER_FQDN):443:$VIP_ROUTER" "https://$ROUTER_FQDN/"
# 5.2 Enrutado a la Route
if ($NEEDS_HOST_H) {
  curl.exe -kI --resolve "$($ROUTER_FQDN):443:$VIP_ROUTER" -H ("Host: "+$HOST_HEADER) "https://$ROUTER_FQDN/"
} else {
  curl.exe -kI --resolve "$($ROUTER_FQDN):443:$VIP_ROUTER" "https://$ROUTER_FQDN/"
}

Write-Host "`nListo." -ForegroundColor Green

# ===== 6) ROLLBACK (si algo falla): descomenta y ejecuta de nuevo este .ps1 =====
# oc.exe -n $NS replace -f $backup
