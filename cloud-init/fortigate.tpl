Content-Type: multipart/mixed; boundary="==FORTIGATE-BOOTSTRAP=="
MIME-Version: 1.0

--==FORTIGATE-BOOTSTRAP==
Content-Type: text/plain; charset="us-ascii"

config system auto-update
    set status disable
end
execute vm-licence ${var_fortiflex_token}
--==FORTIGATE-BOOTSTRAP==--
