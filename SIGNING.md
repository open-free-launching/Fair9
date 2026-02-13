# Signing Fair9

To sign the Windows executable for distribution:

1.  **Generate Certificate**:
    ```powershell
    New-SelfSignedCertificate -Type CodeSigningCert -Subject "CN=OpenFL" -CertStoreLocation Cert:\CurrentUser\My
    ```

2.  **Export PFX**:
    Export the certificate to `OpenFL.pfx`.

3.  **Sign**:
    ```powershell
    signtool sign /f OpenFL.pfx /p <password> /fd SHA256 /t http://timestamp.digicert.com /v build\windows\runner\Release\fairnine_flutter.exe
    ```
