# Script para atualizar registros no CPANEL

## Adaptado por Rafael Arcanjo <rafael.wzs@gmail.com>
## Adaptado para Jefferson T @azurewebr

### Pré instalação
#### Criar o record DNS que será atualizado no CPANEL antes de iniciar a execução
- **Nome** => subdomínio e domínio que será atualizado (ex.: teste.l2kally.com);
- **TTL** => 1;
- **Classe** => IN;
- **Tipo** => A;
- **Registro** => IP inicial (ex.: 45.185.208.50).

### Instalação
#### Mover todos os arquivos para a pasta /usr/local/updatedns
#### Dar permissão de execução para o arquivo updatedns.sh
```chmod +x updatedns.sh```

#### Informar os IPs que serão monitorados no arquivo ips, UM POR LINHA

### Configuração
#### Configurar as variáveis dentro do updatedns.sh:
- **CONTACT_EMAIL** => Desconsiderar, de uso do script original;
- **DOMAIN** => Domínio DNS que será atualizado (ex.: l2kally.com);
- **SUBDOMAIN** => Registro DNS que será atualizado (ex.: teste);
- **CPANEL_SERVER** => Servidor do CPANEL (ex.: 45.185.208.181);
- **CPANEL_USER** => Usuário do CPANEL (ex.: l2kally);
- **CPANEL_PASS** => Senha do CPANEL (ex.: dnsfailover2020);
- **QUIET** => Debug, se não configurado, ativa o debug. Se configurado com 1, ativa o modo silencioso (ex.: 1);
- **FILE_IPS** => Arquivo onde estão os IPs;
- **WAITING** => Tempo de aguardo entre os loops (ex.: 1s = *um segundo* / 1m = *um minuto* / 1h = *uma hora* / 0s = *sem espera*).

### Execução
```/usr/local/updatedns/updatedns.sh```

### Inicio automático
Execute os seguintes comandos como root:
```chmod u+x /etc/rc.d/rc.local```
```echo "/usr/local/updatedns/updatedns.sh &" >> /etc/rc.d/rc.local```