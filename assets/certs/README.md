# Certificates

This directory must exist at build time because `pubspec.yaml` declares
`assets/certs/` as an asset bundle. The runtime loader
(`lib/customer_display/nearpay/nearpay_service.dart`) tolerates a missing
cert via try/catch — NearPay just stays disabled — so a CI build with no
real certificate still produces a working binary.

## For production / signed builds

`developer_cert.pem` is a NearPay developer certificate and is NOT committed
to this repository. To make it available during a Codemagic build:

1. In Codemagic, open the app → **Workflow Editor** → **Environment
   variables** → **Secure files** (or **Build machine** → **Environment
   variables** if using the YAML editor).
2. Upload `developer_cert.pem` under a name like `DEVELOPER_CERT_PEM`.
3. Add a pre-build script step to `codemagic.yaml` that writes the file
   into this directory before `flutter build`:

   ```yaml
   - name: Restore NearPay developer cert
     script: |
       if ($env:DEVELOPER_CERT_PEM) {
         New-Item -ItemType Directory -Force -Path assets\certs | Out-Null
         [System.IO.File]::WriteAllText(
           "assets\certs\developer_cert.pem",
           $env:DEVELOPER_CERT_PEM
         )
       } else {
         Write-Host "⚠️ DEVELOPER_CERT_PEM not set — NearPay will run disabled."
       }
   ```

Builds without the secret will still succeed; NearPay just logs the
missing cert once and keeps the rest of the app functional.
