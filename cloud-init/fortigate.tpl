Content-Type: multipart/mixed; boundary="==FORTIGATE-BOOTSTRAP=="
MIME-Version: 1.0

--==FORTIGATE-BOOTSTRAP==
Content-Type: text/plain; charset="us-ascii"

config system auto-update
    set status disable
end
config vpn certificate local
    edit "fullchain"
        set private-key "${var_privkey_pem}"
        set certificate "${var_fullchain_pem}"
    next
end
config vpn certificate ca
    edit "LetsEncrypt_CA"
        set ca "${var_chain_pem}"
    next
end
config system global
    set admin-server-cert "fullchain"
end
execute vm-licence ${var_fortiflex_token}
--==FORTIGATE-BOOTSTRAP==--
