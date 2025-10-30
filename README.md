# On-Premise Sunucu Simülasyonu ve .NET Uygulama Deployment Otomasyonu

## İçindekiler
- [Genel Bakış](#genel-bakış)
- [Mimari ve Bileşenler](#mimari-ve-bileşenler)
- [Önkoşullar](#önkoşullar)
- [Kurulum Adımları](#kurulum-adımları)
- [Otomasyon Scripti Detayları](#otomasyon-scripti-detayları)
- [Terraform Yapılandırması](#terraform-yapılandırması)
- [Ansible Playbook'ları](#ansible-playbookları)
- [Inventory Yapılandırması](#inventory-yapılandırması)
- [Sorun Giderme](#sorun-giderme)
- [Güvenlik Notları](#güvenlik-notları)

## Genel Bakış

Bu proje, Azure üzerinde on-premise sunucu ortamını simüle eden bir altyapı kurulumu ve .NET uygulamasının otomatik deployment sürecini içermektedir. 

### Proje Amacı
Terraform ile 2 adet on-premise server'ı simüle edecek sunucu oluşturulur:
1. **Linux Server (Ubuntu 22.04)**: PostgreSQL veritabanı sunucusu
2. **Windows Server 2022**: IIS üzerinde .NET 9.0 uygulaması barındırma sunucusu

Ansible ile bu sunucular üzerinde gerekli tüm yapılandırmalar otomatik olarak gerçekleştirilir ve uygulama deploy edilir.

## Mimari ve Bileşenler

### Altyapı Bileşenleri
- **Resource Group**: Tüm kaynakları içeren Azure kaynak grubu
- **Virtual Network**: 10.0.0.0/16 adres aralığı
- **Subnet**: 10.0.1.0/24 adres aralığı
- **Public IP'ler**: Her iki sunucu için static public IP
- **Network Security Groups**: 
  - Linux NSG: SSH (22), PostgreSQL (5432)
  - Windows NSG: RDP (3389), HTTP (80), HTTPS (443), WinRM (5985, 5986)

### Workspace Ortamları
Proje 3 farklı ortamı destekler:
- **dev**: Geliştirme ortamı
- **staging**: Test ortamı
- **prod**: Üretim ortamı

Her ortam için ayrı tfvars dosyası ve SSH key çifti kullanılır.

## Önkoşullar

### Gerekli Araçlar
```bash
# Terraform (v1.0+)
terraform --version

# Ansible (v2.9+)
ansible --version

# Azure CLI
az --version

# jq (JSON işleme)
jq --version

# Git
git --version
```

### Gerekli Python Paketleri
```bash
pip install pywinrm
pip install requests-ntlm
```

### Azure Yapılandırması
```bash
# Azure'a giriş yapın
az login

# Subscription ID'nizi not edin
az account show --query id -o tsv
```

### Dosya Yapısı
```
.
├── infra.sh                           # Ana otomasyon scripti
├── terraform-infra/
│   ├── providers.tf                   # Provider yapılandırması
│   ├── variables.tf                   # Terraform değişkenleri
│   ├── main.tf                        # Ana altyapı tanımları
│   ├── dev.tfvars                     # Dev ortam değişkenleri
│   ├── staging.tfvars                 # Staging ortam değişkenleri
│   └── prod.tfvars                    # Prod ortam değişkenleri
└── ansible/
    ├── inventory-http.ini             # HTTP WinRM inventory
    ├── inventory-https.ini            # HTTPS WinRM inventory
    ├── appsettings.json               # .NET uygulama yapılandırması
    ├── 01-install_iis_https_listener_setup.yaml
    ├── 02-install_dotnet_sdk_other_tools.yaml
    ├── 03-deploy_windows_app.yaml
    └── 04-add-website_app_pool.yaml
```

## Kurulum Adımları

### 1. Repoyu Klonlayın
```bash
git clone <repo-url>
cd <project-directory>
```

### 2. Terraform Değişkenlerini Yapılandırın
`terraform-infra/prod.tfvars` dosyasını düzenleyin:
```hcl
admin_username = "produser"
linux_vm_size = "Standard_D4as_v5"
windows_vm_size = "Standard_D4as_v5"
ssh_public_key_path = "~/.ssh/case-prod.pub"
ssh_private_key_path = "~/.ssh/case-prod"
admin_password = "GüçlüŞifreniz123!"
```

### 3. Azure Subscription ID'yi Ayarlayın
`terraform-infra/providers.tf` dosyasında subscription_id değerini güncelleyin:
```hcl
provider "azurerm" {
  features {}
  subscription_id = "your-subscription-id-here"
}
```

### 4. Ansible Inventory Dosyalarını Yapılandırın
`ansible/inventory-http.ini` ve `ansible/inventory-https.ini` dosyalarında:
```ini
[windows:vars]
winserver_user="produser"
winserver_password="GüçlüŞifreniz123!"
```

### 5. Otomasyon Scriptini Çalıştırın
```bash
chmod +x infra.sh
./infra.sh
```

## Otomasyon Scripti Detayları

`infra.sh` scripti aşağıdaki adımları otomatik olarak gerçekleştirir:

### 1. İşlem ve Ortam Seçimi
Script başlatıldığında kullanıcıdan:
- **İşlem türü**: Apply (kurulum) veya Destroy (silme)
- **Ortam**: dev, staging veya prod

### 2. SSH Key Yönetimi
```bash
# Key path: ~/.ssh/case-{workspace}
# Örnek: ~/.ssh/case-prod
```
- Mevcut key varsa üzerine yazma onayı istenir
- Yeni key otomatik oluşturulur
- İzinler otomatik ayarlanır (400 private, 644 public)

### 3. Terraform İşlemleri
```bash
# Terraform dizinine geçiş
cd terraform-infra

# Init ve workspace yönetimi
terraform init
terraform workspace select ${WORKSPACE} || terraform workspace new ${WORKSPACE}

# Plan ve Apply
terraform plan -var-file="${WORKSPACE}.tfvars"
terraform apply -var-file="${WORKSPACE}.tfvars" -auto-approve
```

### 4. Terraform Output'larını Alma
Script aşağıdaki bilgileri otomatik olarak alır:
- PostgreSQL sunucu public IP
- Windows sunucu public IP
- Admin kullanıcı adı

### 5. PostgreSQL Veritabanı Doğrulama
```bash
# 15 saniye bekleme (VM başlatma için)
# 8 deneme, her biri arasında 8 saniye
# SSH ile bağlanıp veritabanı kontrolü
```

Kontrol edilen:
- PostgreSQL servisinin çalışıp çalışmadığı
- `mkanus` veritabanının oluşturulup oluşturulmadığı

### 6. Inventory Dosyalarını Güncelleme
```bash
# inventory-http.ini ve inventory-https.ini dosyalarında
# winserver_host değeri Windows sunucu IP'si ile güncellenir
```

### 7. appsettings.json Güncelleme
```bash
# PostgreSQL Host IP adresi otomatik güncellenir
# Regex ile "Host=IP_ADDRESS;" formatındaki değer değiştirilir
```

### 8. Ansible Playbook'ların Sıralı Çalıştırılması

#### 8.1. IIS ve HTTPS Listener Kurulumu
```bash
ansible-playbook -i inventory-http.ini 01-install_iis_https_listener_setup.yaml
```
- WinRM HTTP üzerinden ilk bağlantı
- IIS kurulumu
- Self-signed SSL sertifikası oluşturma
- WinRM HTTPS listener yapılandırması
- Güvenlik ayarları (NTLM, encryption)

#### 8.2. .NET SDK ve Araçların Kurulumu
```bash
ansible-playbook -i inventory-https.ini 02-install_dotnet_sdk_other_tools.yaml
```
- WinRM HTTPS üzerinden güvenli bağlantı
- .NET Hosting Bundle 9.0.10
- .NET SDK 9.0.111
- Git for Windows 2.51.1
- CertifyTheWeb (SSL yönetimi)

#### 8.3. .NET Uygulamasının Deploy Edilmesi
```bash
ansible-playbook -i inventory-https.ini 03-deploy_windows_app.yaml
```
- GitHub'dan uygulama klonlama
- .NET publish işlemi
- Publish dizinine kopyalama
- appsettings.json dosyasının transfer edilmesi

#### 8.4. IIS Website ve Application Pool Yapılandırması
```bash
ansible-playbook -i inventory-https.ini 04-add-website_app_pool.yaml
```
- Application Pool oluşturma (.NET Core için "No Managed Code")
- Default Web Site'ı durdurma
- Yeni IIS website oluşturma
- HTTP binding yapılandırması (Port 80)
- Host header ayarlama

## Terraform Yapılandırması

### Providers.tf
```hcl
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.37.0"
    }
  }
}
```

### Linux VM (PostgreSQL)
- **OS**: Ubuntu 22.04 LTS
- **Cloud-init Script**: 
  - PostgreSQL 14 kurulumu
  - `mkanus` veritabanı ve kullanıcısı oluşturma
  - Uzaktan erişim yapılandırması (0.0.0.0/0)
  - md5 authentication

### Windows VM (IIS)
- **OS**: Windows Server 2022 Datacenter
- **Custom Script Extension**: 
  - WinRM HTTP listener otomatik kurulumu
  - Basic authentication etkinleştirme
  - Firewall kuralı ekleme

## Ansible Playbook'ları

### 1. install_iis_https_listener_setup.yaml
**Amaç**: IIS kurulumu ve WinRM HTTPS yapılandırması

**Görevler**:
- PowerShell Remoting etkinleştirme
- WinRM servisini başlatma
- Self-signed SSL sertifikası oluşturma
- WinRM HTTPS listener ekleme
- NTLM authentication yapılandırması
- Firewall kuralları

**Önemli Notlar**:
- İlk bağlantı HTTP (5985) üzerinden yapılır
- HTTPS listener eklendikten sonra sonraki playbook'lar HTTPS kullanır

### 2. install_dotnet_sdk_other_tools.yaml
**Amaç**: Geliştirme araçlarının kurulumu

**İndirilen Dosyalar**:
| Araç | Versiyon | Boyut |
|------|----------|-------|
| .NET Hosting Bundle | 9.0.10 | ~350 MB |
| .NET SDK | 9.0.111 | ~250 MB |
| Git for Windows | 2.51.1 | ~50 MB |
| CertifyTheWeb | 6.1.11 | ~30 MB |

**Özellikler**:
- `force: no` parametresi ile tekrar indirme önlenir
- Git PATH ortam değişkenine eklenir
- Silent kurulum parametreleri kullanılır

### 3. deploy_windows_app.yaml
**Amaç**: GitHub'dan uygulama çekme ve publish etme

**Değişkenler**:
```yaml
repo_url: "https://github.com/mehmetkanus17/app-devops.git"
repo_dir: "C:\\Users\\produser\\app-devops"
publish_dir: "C:\\inetpub\\wwwroot\\case-app"
```

**İşlem Akışı**:
1. Repository klonlama veya güncelleme (git pull)
2. PowerShell deployment scripti oluşturma
3. `dotnet publish` komutu ile uygulama derleme
4. appsettings.json dosyasını publish dizinine kopyalama

**Publish Komutu**:
```powershell
dotnet publish -c Release --self-contained false -o C:\inetpub\wwwroot\case-app /p:TargetFramework=net9.0
```

### 4. add-website_app_pool.yaml
**Amaç**: IIS website ve application pool yapılandırması

**Yapılandırma**:
```yaml
site_name: "dotnet.mehmetkanus.com"
site_physical_path: "C:\\inetpub\\wwwroot\\case-app"
site_port: 80
dotnet_version: ""  # .NET Core için boş string
```

**Görevler**:
- Application Pool oluşturma (Integrated Pipeline)
- managedRuntimeVersion: "" (No Managed Code - .NET Core)
- Default Web Site'ı durdurma
- Yeni website oluşturma ve başlatma
- HTTP binding: `*:80:dotnet.mehmetkanus.com`

## Inventory Yapılandırması

### inventory-http.ini (İlk Bağlantı)
```ini
[windows]
winserver-iis winserver_host=<DYNAMIC_IP>

[windows:vars]
winserver_user="produser"
winserver_password="GüçlüŞifreniz123!"
winserver_connection=winrm
winserver_winrm_transport=ntlm
winserver_port=5985
winserver_winrm_scheme=http
winserver_winrm_message_encryption=always
winserver_winrm_server_cert_validation=ignore
winserver_shell_type=powershell
```

### inventory-https.ini (Güvenli Bağlantı)
```ini
[windows]
winserver-iis winserver_host=<DYNAMIC_IP>

[windows:vars]
winserver_user="produser"
winserver_password="GüçlüŞifreniz123!"
winserver_connection=winrm
winserver_winrm_transport=ntlm
winserver_port=5986
winserver_winrm_scheme=https
winserver_winrm_message_encryption=always
winserver_winrm_server_cert_validation=ignore
winserver_shell_type=powershell
```

**Not**: `winserver_host` değeri `infra.sh` scripti tarafından otomatik güncellenir.

### 📂 Güvenli Inventory Yapılandırması (Ansible Vault ile)

Üretim ortamında şifreleri düz metin olarak saklamak yerine **Ansible Vault** kullanarak şifreleyin:

#### inventory.ini (Vault ile Güvenli)
```ini
[windows]
winserver-iis ansible_host=123.45.678.9

[windows:vars]
ansible_user=produser
ansible_password: !vault |
          $ANSIBLE_VAULT;1.1;AES256
          36656463393966663303136576785633662643433355623361383432343830303636326432303937
          3737636339633162653545338651366339646637656561300a326136336137613564326233306537
          37323662393261376331373466343562343432353763353039306564646235666239636136333965
          6161616638393264330a663334613635393137373033333331346362393064623261383831353962
          3038
ansible_connection=winrm
ansible_winrm_transport=ntlm
ansible_port=5986
ansible_winrm_scheme=https
ansible_winrm_message_encryption=always
ansible_winrm_server_cert_validation=ignore
ansible_shell_type=powershell
```

#### 🔹 Şifre Şifreleme Komutu
Parolanızı düz metin yazmak yerine ansible-vault ile şifreleyin:
```bash
ansible-vault encrypt_string 'xxxxxxxxxxxx' --name 'ansible_password'
```

Çıktıyı yukarıdaki inventory dosyasına yapıştırın (`!vault |` kısmını Vault çıktısıyla değiştirin).

#### 📜 Bağlantı Test Playbook'u

**test-winrm-https.yml**
```yaml
---
- name: Test NTLM over HTTPS WinRM Connection
  hosts: windows
  gather_facts: no

  tasks:
    - name: Test connectivity
      win_ping:

    - name: Show connected hostname
      win_shell: Write-Host "Connected securely to $(hostname)"
```

#### ▶️ Vault ile Playbook Çalıştırma
```bash
ansible-playbook -i inventory.ini test-winrm-https.yml --ask-vault-pass
```

(Vault kullanıyorsanız şifre isteyecektir.)

## Sorun Giderme

### Terraform İşlemleri

#### Problem: "Workspace not found"
```bash
# Çözüm: Workspace'i manuel oluşturun
cd terraform-infra
terraform workspace new prod
```

#### Problem: "Authentication failed"
```bash
# Çözüm: Azure'a tekrar login olun
az login
az account set --subscription "your-subscription-id"
```

### Ansible Bağlantı Sorunları

#### Problem: "WinRM connection timeout"
```bash
# Kontroller:
1. Windows VM'in NSG kurallarını kontrol edin
2. WinRM servisinin çalıştığını doğrulayın
3. Firewall kurallarını kontrol edin

# Test bağlantısı:
curl -v http://<WINDOWS_IP>:5985/wsman
```

#### Problem: "Authentication failure"
```bash
# Çözüm:
1. inventory dosyasındaki kullanıcı adı ve şifreyi kontrol edin
2. Windows VM'de kullanıcının varlığını doğrulayın
3. WinRM Basic authentication'ın etkin olduğunu kontrol edin
```

### PostgreSQL Bağlantı Sorunları

#### Problem: "Connection refused"
```bash
# Kontroller:
1. PostgreSQL servisinin çalıştığını kontrol edin
ssh -i ~/.ssh/case-prod produser@<POSTGRES_IP> "sudo systemctl status postgresql"

2. Port 5432'nin dinlediğini kontrol edin
ssh -i ~/.ssh/case-prod produser@<POSTGRES_IP> "sudo netstat -tulpn | grep 5432"

3. pg_hba.conf dosyasını kontrol edin
ssh -i ~/.ssh/case-prod produser@<POSTGRES_IP> "sudo cat /etc/postgresql/14/main/pg_hba.conf"
```

### .NET Uygulaması Sorunları

#### Problem: "502 Bad Gateway"
```bash
# Çözüm:
1. Application Pool'un çalıştığını kontrol edin
2. .NET Hosting Bundle'ın kurulu olduğunu doğrulayın
3. appsettings.json'daki connection string'i kontrol edin
4. Event Viewer'da uygulama loglarını inceleyin
```

#### Problem: "Database connection failed"
```bash
# Çözüm:
1. appsettings.json'daki PostgreSQL IP'sini kontrol edin
2. PostgreSQL'in uzaktan bağlantılara izin verdiğini doğrulayın
3. Veritabanı kullanıcı adı ve şifresini kontrol edin
```

## Güvenlik Notları

### Önerilen Güvenlik İyileştirmeleri

#### 1. Network Security Groups
Mevcut yapılandırmada tüm kaynaklara `*` (0.0.0.0/0) erişimi vardır. Üretim ortamında:

```hcl
# SSH - Sadece Ansible control node
source_address_prefix = var.control_public_ip

# RDP - Sadece yönetici IP'leri
source_address_prefix = "YOUR_ADMIN_IP/32"

# WinRM - Sadece Ansible control node
source_address_prefix = var.control_public_ip

# PostgreSQL - Sadece Windows sunucu
source_address_prefix = azurerm_network_interface.nic["windows-kaynak"].private_ip_address
```

#### 2. Şifre Yönetimi
```bash
# Şifreleri Azure Key Vault'ta saklayın
# tfvars dosyalarını .gitignore'a ekleyin
echo "*.tfvars" >> .gitignore

# Ansible Vault kullanın
ansible-vault create ansible/secrets.yml
ansible-vault encrypt ansible/inventory-*.ini
```

#### 3. SSL Sertifikaları
Üretim için self-signed sertifika yerine:
- Let's Encrypt ile ücretsiz SSL sertifikası
- CertifyTheWeb kullanarak otomatik yenileme
- Azure Application Gateway ile SSL termination

#### 4. Windows Güvenlik Sıkılaştırması
```powershell
# WinRM Basic Auth'u kapatın (NTLM yeterli)
winrm set winrm/config/service/auth @{Basic="false"}

# AllowUnencrypted'ı kapatın
winrm set winrm/config/service @{AllowUnencrypted="false"}

# Sadece HTTPS kullanın
winrm delete winrm/config/Listener?Address=*+Transport=HTTP
```

#### 5. PostgreSQL Güvenlik
```bash
# pg_hba.conf - Sadece Windows sunucuya izin verin
host    mkanus    mkanus    <WINDOWS_PRIVATE_IP>/32    md5

# SSL zorunlu hale getirin
ssl = on
ssl_cert_file = '/etc/ssl/certs/server.crt'
ssl_key_file = '/etc/ssl/private/server.key'
```

### Secrets Yönetimi

#### Hassas Bilgileri Saklamayın
```bash
# .gitignore dosyasına ekleyin:
*.tfvars
*.pem
*.key
**/inventory*.ini
appsettings.json
```

#### Environment Variables Kullanın
```bash
export TF_VAR_admin_password="GüçlüŞifreniz123!"
export TF_VAR_subscription_id="subscription-id"
```

## Ek Bilgiler

### Maliyet Optimizasyonu
- **VM Sizes**: dev ortamında daha küçük VM'ler kullanın (Standard_B2s)
- **Auto-shutdown**: Azure'da VM'ler için otomatik kapanma ayarlayın
- **Reserved Instances**: Uzun vadeli kullanım için rezerve instance satın alın

### Monitoring ve Logging
```bash
# Azure Monitor ile VM metriklerini izleyin
# Application Insights ile uygulama performansını takip edin
# Log Analytics workspace oluşturun
```

### Yedekleme Stratejisi
```bash
# PostgreSQL otomatik yedekleme
# Azure Backup ile VM snapshot'ları
# Git repository'ye code backup
```

### İletişim ve Destek
Sorularınız için issue açabilir veya projeyi fork'layabilirsiniz.

---

**Not**: Bu README, projenin tam kapsamlı dokümantasyonunu içermektedir. Üretim ortamına geçmeden önce güvenlik ayarlarını mutlaka gözden geçirin ve sıkılaştırın.