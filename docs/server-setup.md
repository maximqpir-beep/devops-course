# Конфигурация виртуальной машины devops-vm

Практическая работа №5. Бахметьев Максим, ЭФБО-12-24.
Дата проверки: 25.10.2026. Сведения подтверждены скриншотами выполнения.

## 1. Параметры машины

- VirtualBox, имя машины: devops-vm.
- Гостевая ОС: Ubuntu Server 24.04.5 LTS, x86_64, без графической оболочки.
- Оперативная память: 2048 МБ.
- Процессор: 2 виртуальных ядра.
- Виртуальный диск: VDI, 25 ГБ, динамическое выделение места.
- Для размещения машины выбран диск D: хостового компьютера: при создании на C: возникла ошибка VERR_DISK_FULL.
- Обновления установлены через apt. На следующую версию Ubuntu система не обновлялась.
- Размер корневого раздела / меньше полной ёмкости VDI; это не изменение размера виртуального диска.

## 2. Сетевые интерфейсы

| Интерфейс | Тип | Адрес на момент проверки | Назначение |
| --- | --- | --- | --- |
| enp0s3 | NAT | 10.0.2.15/24 | Интернет, обновления и SSH через проброс |
| enp0s8 | Host-only | 192.168.56.101/24 | Прямой доступ с Windows и последующие веб-службы |

Адрес Windows в Host-only: 192.168.56.1.
Адреса назначены DHCP и проверяются после запуска командой ip -brief address; при смене адреса необходимо обновить клиентские настройки.

## 3. Правило проброса портов

| Имя | Протокол | Адрес хоста | Порт хоста | Адрес гостя | Порт гостя |
| --- | --- | --- | --- | --- | --- |
| ssh, исходное состояние | TCP | 127.0.0.1 | 2222 | пусто | 22 |
| ssh, итоговое состояние | TCP | 127.0.0.1 | 2222 | пусто | 2222 |

После изменения гостевого порта проброс первоначально обрывал подключения. Прямой вход через Host-only работал. После выключения и запуска VM восстановлен вход через NAT командой ssh devops.

## 4. Учётные записи

- student: исходная учётная запись установки, UID 1000, доступ к sudo. После hardening не допускается по SSH из-за AllowUsers devops; остаётся доступ через консоль VirtualBox.
- devops: UID 1001, группы devops, sudo, users; SSH-аутентификация по отдельному ключу.
- root: прямой SSH-вход запрещён.
- Пароли в репозитории не хранятся.

Отдельный клиентский ключ создан на Windows: ~/.ssh/devops_vm, публичная часть ~/.ssh/devops_vm.pub. Закрытый ключ не копировать на сервер и не помещать в Git.
На сервере: /home/devops/.ssh имеет права 700, authorized_keys — 600; владельцем является devops.

Конфигурация Windows, файл ~/.ssh/config:

~~~sshconfig
Host devops
    HostName 127.0.0.1
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes
~~~

При первом подключении отпечаток ED25519 сверялся с выводом следующей команды в консоли VirtualBox:

~~~bash
sudo ssh-keygen -l -f /etc/ssh/ssh_host_ed25519_key.pub
~~~

## 5. Служба SSH

Резервная копия основного файла: /etc/ssh/sshd_config.backup.
Основной файл включает каталог /etc/ssh/sshd_config.d/.
Настройки находятся в /etc/ssh/sshd_config.d/99-hardening.conf:

~~~text
Port 2222
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
AllowUsers devops
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
~~~

Проверка: sudo sshd -t и sudo sshd -T.
При выполнении работы активных конфликтующих директив в других файлах не обнаружено. При воспроизведении снова проверить: OpenSSH использует первое установленное значение большинства параметров.

Сокетная активация ssh.socket отключена, ssh.service включена:

~~~bash
sudo systemctl disable --now ssh.socket
sudo systemctl enable --now ssh.service
sudo systemctl restart ssh
sudo ss -tlnp | grep sshd
~~~

Подтверждено прослушивание IPv4 и IPv6 на порту 2222.
Во время изменения конфигурации сохранялась действующая сессия; новое подключение проверялось отдельно.
До hardening сервер предлагал publickey,password; после изменения парольный вход отвергается, как и вход root.

## 6. Правила межсетевого экрана

UFW активен, включён при загрузке. Политики: deny incoming, allow outgoing, disabled routed.
Логирование: medium.

| Порт TCP | Правило | Назначение |
| --- | --- | --- |
| 2222 | LIMIT IN | SSH с ограничением частоты |
| 80 | ALLOW IN | HTTP для ПР №6 |
| 443 | ALLOW IN | HTTPS |
| прочие | политика deny | Запрет незапрошенных входящих соединений |

Правила действуют для IPv4 и IPv6.
Разрешение SSH было добавлено до включения UFW. Новое подключение после включения проверено командой ssh devops whoami.

Итоговые настройки для восстановления:

~~~bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw limit 2222/tcp comment 'SSH rate-limited'
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw logging medium
sudo ufw enable
sudo ufw status verbose
~~~

Не оставлять дополнительное ALLOW для 2222: оно может обходить ограничение LIMIT. В выполненной конфигурации ufw limit заменил прежнее allow; последующая попытка удаления allow сообщила об отсутствии такого правила.

Проверка закрытого порта с Windows:

~~~bash
curl -m 3 http://192.168.56.101:8080
~~~

Получен тайм-аут. На сервере журнал содержит UFW BLOCK: SRC=192.168.56.1, DST=192.168.56.101, PROTO=TCP, DPT=8080.

~~~bash
sudo journalctl -k --since "5 minutes ago" --no-pager | grep 'UFW BLOCK' | tail -5
~~~

## 7. Снимки состояния

| Снимок | Момент создания |
| --- | --- |
| 01-clean-install | После установки и обновления Ubuntu, настройки интерфейсов и установки OpenSSH; до создания devops |
| 02-keys-configured | После создания devops, настройки ключа, прав .ssh и клиентского псевдонима |
| 03-ssh-hardened | После изменения порта, запрета root и паролей, проверки доступа и журналов; до настройки UFW и локального имени |

Снимки образуют последовательную цепочку. Последующие изменения UFW, hosts и файл аудита не входят в 03-ssh-hardened.
VM сохраняется для следующих практических работ.

## 8. Веб-сервер

Установленный пакет: nginx 1.24.0 (Ubuntu). Конфигурация отдельного сайта находится в /etc/nginx/sites-available/devops-site; включённая ссылка — /etc/nginx/sites-enabled/devops-site. Стандартная конфигурация sites-enabled/default отключена.

Каталог сайта: /var/www/devops-site, владелец devops:devops, режим 755. Файлы index.html и 404.html принадлежат devops:devops, режим 644. Рабочие процессы www-data читают файлы, но не могут изменять их. Права записи для остальных пользователей запрещены.

Сайт перенаправляет HTTP с порта 80 на HTTPS на порту 443. Разрешены TLS 1.2 и TLS 1.3. Сертификат самоподписанный, содержит SAN DNS:devops.local, действует 365 дней. Он находится в /etc/ssl/certs/devops.crt (root:root, 644). Закрытый ключ /etc/ssl/private/devops.key (root:root, 600); в Git ключ не помещается.

Команда выпуска сертификата:

~~~bash
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/devops.key \
  -out /etc/ssl/certs/devops.crt \
  -subj "/CN=devops.local" \
  -addext "subjectAltName=DNS:devops.local"
~~~

Конфигурация использует server_name devops.local, root /var/www/devops-site, index index.html и отдельные журналы /var/log/nginx/devops-site.access.log и /var/log/nginx/devops-site.error.log. Доставка выполняется scripts/deploy.sh с rsync и правами --chmod=D755,F644. После ручных изменений сервер восстанавливается повторным запуском сценария.

## 9. Локальные имена

В Windows, C:\Windows\System32\drivers\etc\hosts:

~~~text
192.168.56.101    devops.local
~~~

Запись должна находиться в hosts без расширения, без # в начале строки. Сначала была ошибочно создана копия hosts.txt. Затем редактирование настоящего hosts блокировалось Dr.Web. Для сохранения разрешено изменение только объекта «Файл HOSTS»; после редактирования следует вернуть блокировку. Весь антивирус отключать не требуется.

После сохранения:

~~~powershell
ipconfig /flushdns
ping -n 2 devops.local
~~~

Проверено разрешение в 192.168.56.101 и два успешных ответа.
Подключение с Windows:

~~~bash
ssh -i ~/.ssh/devops_vm -o IdentitiesOnly=yes -p 2222 devops@devops.local
~~~

Запись Windows не меняет разрешение имён внутри Ubuntu.
Имя Ubuntu: devops-vm. В /etc/hosts сервера:

~~~text
127.0.1.1 devops-vm.devops.local devops-vm
~~~

Резервная копия серверного файла: /etc/hosts.pr5.backup.
hostname -f возвращает devops-vm.devops.local.

## 10. Аудит конфигурации

Файл в репозитории: scripts/audit.sh. Запуск на Ubuntu:

~~~bash
bash scripts/audit.sh
echo "Exit code: $?"
~~~

Шесть проверок: PermitRootLogin=no, PasswordAuthentication=no, отсутствие порта 22 в конфигурации SSH, MaxAuthTries=3, активность UFW, deny incoming.

Подтверждены два случая:
- правильная конфигурация: Passed: 6; Failed: 0; Exit code: 0;
- временное MaxAuthTries=10: Passed: 5; Failed: 1; Exit code: 1.

Значение восстановлено в 3, sshd -t выполнен успешно, повторный аудит вернул 0.
Служба во время отрицательного теста не перезапускалась: скрипт читает конфигурацию на диске, а не проверяет поведение работающего процесса.

## 11. Восстановление после отката на 01-clean-install

Откат уничтожает последующие изменения текущего состояния; выполнять только по заданию преподавателя, сохранив нужные файлы вне VM.

1. Вернуть проброс NAT к хост 2222 → гость 22, запустить VM. В консоли проверить ip -brief address и systemctl status ssh.
2. Подключиться с Windows: ssh -p 2222 student@127.0.0.1. При изменении ключа хоста сначала сверить отпечаток через консоль, а не удалять known_hosts вслепую.
3. На сервере выполнить sudo adduser devops и sudo usermod -aG sudo devops.
4. На Windows использовать существующий отдельный ключ devops_vm и установить публичную часть командой ssh-copy-id -i ~/.ssh/devops_vm.pub -p 2222 devops@127.0.0.1.
5. Проверить вход по ключу и права 700/600, при необходимости исправить их от имени devops.
6. Сохранить резервную копию sshd_config и создать 99-hardening.conf с точным содержимым раздела 5. Проверить отсутствие конфликтующих более ранних настроек, затем sudo sshd -t и sudo sshd -T.
7. Не закрывая рабочую сессию, отключить ssh.socket, включить ssh.service и перезапустить SSH командами раздела 5.
8. Изменить гостевой порт проброса с 22 на 2222. В отдельном окне проверить ssh devops; при затруднении проверить прямой вход на фактический Host-only IP и журнал sudo journalctl -u ssh -n 20.
9. Применить команды UFW из раздела 6; SSH-разрешение должно существовать до ufw enable. В новом окне снова проверить доступ.
10. Восстановить серверное полное имя по разделу 8. Запись hosts на Windows сохраняется при откате VM; проверить, что Host-only адрес не изменился.
11. Перенести scripts/audit.sh из репозитория и проверить код 0. Проверить sudo ss -tlnp, sudo ufw status verbose, hostname -f и запрет root/пароля.

Ссылки:
- https://github.com/maximqpir-beep/devops-course
- https://github.com/maximqpir-beep/devops-course/blob/main/scripts/audit.sh

## 12. Контейнеризация приложения (PR 7)

Приложение Flask находится в каталоге `app/`. `Dockerfile` запускает его через Gunicorn от непривилегированного пользователя `app`. `docker-compose.yml` поднимает приложение и PostgreSQL 16: база доступна приложению по имени `db` во внутренней сети Compose, а данные хранятся в томе `app_db_data`.

На сервере секрет базы храни только в `/home/devops/app/.env`; файл не добавляй в Git. Создай его с закрытыми правами:

```bash
cd ~/app
cp .env.example .env
chmod 600 .env
sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$(openssl rand -hex 16)/" .env
docker compose up -d --build
docker compose ps
