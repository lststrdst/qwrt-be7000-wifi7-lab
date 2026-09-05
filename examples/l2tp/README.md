# NETSCOPE L2TP/IPsec client

Этот пример рассчитан на базу QWRT и IKEv1/IPsec transport mode, L2TP и PAP. Я запускаю
strongSwan, xl2tpd и pppd в определённом порядке отдельным управляющим
сценарием.

```text
LAN / удалённый VPN -> office PPP -> 10.20.0.0/16
                                   -> 172.20.50.10/32
```

До подъёма PPP для этих направлений должны существовать blackhole-маршруты.
После подъёма интерфейса добавляются более приоритетные маршруты через PPP.

Файлы с реальными секретами не коммитятся:

```sh
umask 077
install -m 600 ipsec.secrets /etc/ipsec.secrets
install -m 600 pap-secrets /etc/ppp/pap-secrets
```

Для split tunnel я не направляю весь интернет в офисный PPP. Доступу клиентов
из LAN или AWG также нужны отдельные firewall forwarding, MASQUERADE и TCP MSS
clamp под фактическим именем PPP-интерфейса.
