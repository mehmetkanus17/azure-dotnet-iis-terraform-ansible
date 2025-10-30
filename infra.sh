#!/bin/bash
set -euo pipefail

# ============================================================
# Renkler
# ============================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# ============================================================
# Konfig
# ============================================================
TERRAFORM_INFRA_DIR="terraform-infra"
ANSIBLE_DIR="ansible"
INVENTORY_FILE1="${ANSIBLE_DIR}/inventory-http.ini"
INVENTORY_FILE2="${ANSIBLE_DIR}/inventory-https.ini"
APPSETTINGS_FILE="${ANSIBLE_DIR}/appsettings.json"
WEB_SITE="dotnet.mehmetkanus.com"

# ============================================================
# Helper
# ============================================================
err() { echo -e "${RED}[ERR] $*${NC}" >&2; }
info() { echo -e "${GREEN}$*${NC}"; }
warn() { echo -e "${YELLOW}$*${NC}"; }

info "=========================================="
info "  Altyapı ve Konfigürasyon Otomasyonu"
info "=========================================="

# ============================================================
# 1) İşlem seçimi
# ============================================================
while :; do
    echo
    echo "1) Altyapı Kurulumu (terraform apply)"
    echo "2) Altyapı Temizleme (terraform destroy)"
    echo "3) Çıkış"
    read -rp "Seçiminiz (1-3): " action_selection

    case $action_selection in
        1) ACTION="apply"; break ;;
        2) ACTION="destroy"; break ;;
        3) info "Çıkış."; exit 0 ;;
        *) warn "Geçersiz seçim (1-3)." ;;
    esac
done

# ============================================================
# 2) Ortam seçimi
# ============================================================
while :; do
    echo
    echo -e "\n${YELLOW}Lütfen bir Terraform ortamı seçin:${NC}"
    echo "1) dev (Geliştirme Ortamı)"
    echo "2) staging (Staging Ortamı)"
    echo "3) prod (Üretim Ortamı)"
    echo "4) Çıkış"
    read -rp "Seçiminiz (1-4): " environment_selection

    case $environment_selection in
        1) WORKSPACE="dev"; break ;;
        2) WORKSPACE="staging"; break ;;
        3) WORKSPACE="prod"; break ;;
        4) info "Çıkış."; exit 0 ;;
        *) warn "Geçersiz seçim (1-4)." ;;
    esac
done

echo
sleep 1 

info "Seçilen işlem: ${ACTION}"
sleep 1
echo
info "Seçilen ortam : ${WORKSPACE}"
sleep 1
echo
# ============================================================
# Terraform dizinine geçiş
# ============================================================
if [ ! -d "${TERRAFORM_INFRA_DIR}" ]; then
    err "Terraform dizini '${TERRAFORM_INFRA_DIR}' bulunamadı."
    exit 1
fi
cd "${TERRAFORM_INFRA_DIR}"

# ============================================================
# APPLY
# ============================================================
if [ "${ACTION}" = "apply" ]; then
    info "SSH key kontrol ediliyor..."
    sleep 1
    echo
    USERNAME="${WORKSPACE}-user"
    SSH_KEY_PATH="${HOME}/.ssh/case-${WORKSPACE}"

    if [ -f "${SSH_KEY_PATH}" ]; then
        read -rp "SSH anahtarı zaten mevcut (${SSH_KEY_PATH}). Üzerine yazılsın mı? (evet/hayır): " overwrite_key
        if [[ "${overwrite_key}" == "evet" ]]; then
            rm -f "${SSH_KEY_PATH}" "${SSH_KEY_PATH}.pub"
            ssh-keygen -t rsa -f "${SSH_KEY_PATH}" -C "${USERNAME}" -N ""
            info "SSH anahtarı yeniden oluşturuldu."
        else
            info "Mevcut SSH anahtarı kullanılacak."
        fi
    else
        ssh-keygen -t rsa -f "${SSH_KEY_PATH}" -C "${USERNAME}" -N ""
        info "Yeni SSH anahtarı üretildi: ${SSH_KEY_PATH}"
    fi
    chmod 400 "${SSH_KEY_PATH}" || true
    chmod 644 "${SSH_KEY_PATH}.pub" || true

    info "Terraform init..."
    sleep 1
    terraform init -input=false

    # workspace seç / oluştur
    if ! terraform workspace list | grep -q "${WORKSPACE}"; then
        terraform workspace new "${WORKSPACE}"
    else
        terraform workspace select "${WORKSPACE}"
    fi

    info "Terraform plan (${WORKSPACE})..."
    sleep 1
    terraform plan -var-file="${WORKSPACE}.tfvars"

    read -rp "Terraform apply için onayınız (yes/no): " confirm_apply
    if [[ "${confirm_apply}" != "yes" ]]; then
        warn "Terraform apply iptal edildi."
        exit 0
    fi

    info "Terraform apply çalıştırılıyor..."
    sleep 1
    terraform apply -var-file="${WORKSPACE}.tfvars" -auto-approve
    info "Terraform apply tamamlandı."
    echo
    sleep 1

    # ============================================================
    # Terraform Outputs
    # ============================================================
    info "Terraform output değerleri alınıyor..."
    sleep 1

    PUBLIC_IPS_JSON=$(terraform output -json public_ips 2>/dev/null || echo "{}")
    POSTGRES_PUBLIC_IP=$(echo "${PUBLIC_IPS_JSON}" | jq -r '."postgresql-db" // empty')
    WINDOWS_PUBLIC_IP=$(echo "${PUBLIC_IPS_JSON}" | jq -r '."windows-kaynak" // empty')
    ADMIN_USERNAME=$(terraform output -raw admin_username 2>/dev/null || echo "")

    if [ -z "${POSTGRES_PUBLIC_IP}" ]; then
        warn "Postgres public IP alınamadı."
    else
        info "Postgres Public IP: ${POSTGRES_PUBLIC_IP}"
    fi

    if [ -z "${WINDOWS_PUBLIC_IP}" ]; then
        warn "Windows public IP alınamadı."
    else
        info "Windows Public IP: ${WINDOWS_PUBLIC_IP}"
    fi

    if [ -z "${ADMIN_USERNAME}" ]; then
        warn "Admin kullanıcı adı alınamadı."
    else
        info "Admin kullanıcı: ${ADMIN_USERNAME}"
        echo
        sleep 1
    fi

    # ============================================================
    # PostgreSQL doğrulama
    # ============================================================
    if [ -n "${POSTGRES_PUBLIC_IP}" ]; then
        info "PostgreSQL sunucusuna SSH ile bağlanılmadan önce 15 saniye bekleniyor..."
        echo
        sleep 15
        info "PostgreSQL veritabanı kontrolü başlatılıyor..."
        echo
        sleep 1
        RETRIES=8
        SLEEP_SECONDS=8
        DB_OK=0

        for i in $(seq 1 ${RETRIES}); do
            info "Deneme ${i}/${RETRIES}..."
            if ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no -i "${SSH_KEY_PATH}" \
                "${ADMIN_USERNAME}@${POSTGRES_PUBLIC_IP}" \
                "sudo -u postgres psql -lqt | cut -d '|' -f1 | awk '{print \$1}' | grep -qw 'mkanus'"; then
                info "Postgres veritabanı 'mkanus' mevcut."
                echo
                sleep 1
                DB_OK=1
                break
            else
                warn "Postgres bağlantısı başarısız. ${SLEEP_SECONDS}s bekleniyor..."
                sleep "${SLEEP_SECONDS}"
            fi
        done

        if [ "${DB_OK}" -ne 1 ]; then
            warn "Postgres DB kontrolü başarısız (tüm denemeler)."
        fi
    else
        warn "Postgres IP boş olduğu için kontrol atlandı."
    fi

    # ============================================================
    # Inventory file-1 güncelleme
    # ============================================================
    cd ..
    if [ ! -f "${INVENTORY_FILE1}" ]; then
        err "Inventory dosyası bulunamadı: ${INVENTORY_FILE1}"
        exit 1
    fi

    info "Inventory dosyası güncelleniyor: ${INVENTORY_FILE1} -> winserver IP ${WINDOWS_PUBLIC_IP}"
    if grep -qE '^winserver-iis[[:space:]]' "${INVENTORY_FILE1}"; then
        sed -i -E "s|^winserver-iis[[:space:]].*|winserver-iis winserver_host=${WINDOWS_PUBLIC_IP}|" "${INVENTORY_FILE1}"
    else
        echo "winserver-iis winserver_host=${WINDOWS_PUBLIC_IP}" >> "${INVENTORY_FILE1}"
        echo
        sleep 1
    fi

    info "Inventory güncellendi."
    echo
    sleep 1

    # ============================================================
    # Inventory file-2 güncelleme
    # ============================================================
    if [ ! -f "${INVENTORY_FILE2}" ]; then
        err "Inventory dosyası bulunamadı: ${INVENTORY_FILE2}"
        exit 1
    fi

    info "Inventory dosyası güncelleniyor: ${INVENTORY_FILE2} -> winserver IP ${WINDOWS_PUBLIC_IP}"
    if grep -qE '^winserver-iis[[:space:]]' "${INVENTORY_FILE2}"; then
        sed -i -E "s|^winserver-iis[[:space:]].*|winserver-iis winserver_host=${WINDOWS_PUBLIC_IP}|" "${INVENTORY_FILE2}"
    else
        echo "winserver-iis winserver_host=${WINDOWS_PUBLIC_IP}" >> "${INVENTORY_FILE2}"
        echo
        sleep 1
    fi

    info "Inventory güncellendi."
    echo
    sleep 1

    # ============================================================
    # appsettings.json Güncelleme
    # ============================================================    
    if [ -z "${POSTGRES_PUBLIC_IP}" ]; then
        err "HATA: POSTGRES_PUBLIC_IP değişkeni tanımlı değil. Terraform çıktısı kontrol edilmeli."
        exit 1
    fi

    if [ ! -f "${APPSETTINGS_FILE}" ]; then
        err "appsettings dosyası bulunamadı: ${APPSETTINGS_FILE}"
        exit 1
    fi

    info "appsettings.json dosyasındaki Host IP adresi güncelleniyor: ${POSTGRES_PUBLIC_IP}"

    # sed komutu: "Host=" ile başlayan kısmı ve sonundaki ";" arasına yeni IP'yi yerleştirir.
    # Regex: (Host=) (eski IP) (;) -> Host=YENI_IP;
    # \1 -> Host=
    # \2 -> ;
    sed -i -E 's/(Host=)[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}(;)/\1'"${POSTGRES_PUBLIC_IP}"'\2/' "${APPSETTINGS_FILE}"

    info "appsettings.json başarıyla güncellendi."
    echo
    sleep 1

    # ============================================================
    # Ansible 01-install_iis_https_listener_setup playbook çalıştırma
    # ============================================================
    info "Windows VM erişimi için 15 saniye bekleniyor..."
    sleep 15

    cd "${ANSIBLE_DIR}" || { err "Ansible dizinine geçilemedi: ${ANSIBLE_DIR}"; exit 1; }

    info "Ansible 01-install_iis_https_listener_setup playbook başlatılıyor..."
    sleep 1
    ansible-playbook -i inventory-http.ini 01-install_iis_https_listener_setup.yaml || {
        err "Ansible playbook hata ile sonlandı."
        exit 1
    }

    info "Ansible 01-install_iis_https_listener_setup playbook tamamlandı."
    echo
    sleep 1

    # ============================================================
    # Ansible 02-install_dotnet_sdk_other_tools playbook çalıştırma
    # ============================================================

    info "Ansible 02-install_dotnet_sdk_other_tools playbook başlatılıyor..."
    sleep 1
    ansible-playbook -i inventory-https.ini 02-install_dotnet_sdk_other_tools.yaml || {
        err "Ansible 02-install_dotnet_sdk_other_tools playbook hata ile sonlandı."
        exit 1
    }

    info "Ansible 02-install_dotnet_sdk_other_tools playbook tamamlandı."
    sleep 1

    # ============================================================
    # Ansible 03-deploy_windows_app playbook çalıştırma
    # ============================================================

    info "Ansible 03-deploy_windows_app playbook başlatılıyor..."
    sleep 1
    ansible-playbook -i inventory-https.ini 03-deploy_windows_app.yaml || {
        err "Ansible 03-deploy_windows_app playbook hata ile sonlandı."
        exit 1
    }

    info "Ansible 03-deploy_windows_app playbook tamamlandı."
    sleep 1

    # ============================================================
    # Ansible 04-add-website_app_pool playbook çalıştırma
    # ============================================================

    info "Ansible 04-add-website_app_pool playbook başlatılıyor..."
    sleep 1
    ansible-playbook -i inventory-https.ini 04-add-website_app_pool.yaml || {
        err "Ansible 04-add-website_app_pool playbook hata ile sonlandı."
        exit 1
    }

    info "Ansible 04-add-website_app_pool playbook tamamlandı."
    sleep 1

# ============================================================
# DESTROY
# ============================================================
elif [ "${ACTION}" = "destroy" ]; then
    warn "DİKKAT: Bu işlem ${WORKSPACE} ortamındaki tüm altyapıyı silecektir."
    read -rp "Emin misiniz? (evet/hayır): " confirm_destroy
    if [[ "${confirm_destroy}" == "evet" ]]; then
        terraform workspace select "${WORKSPACE}" || true
        terraform destroy -var-file="${WORKSPACE}.tfvars" -auto-approve
        info "Terraform destroy tamamlandı."
    else
        info "Destroy işlemi iptal edildi."
    fi
fi

info "Tüm kurulumlar başarıyla tamamlandı."
