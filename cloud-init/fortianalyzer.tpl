Content-Type: multipart/mixed; boundary="==FORTIANALYZER-BOOTSTRAP=="
MIME-Version: 1.0

--==FORTIANALYZER-BOOTSTRAP==
Content-Type: text/plain; charset="us-ascii"

config system global
    set hostname "${var_faz_vm_name}"
end
%{ if var_fortiflex_token != "" ~}
execute vm-licence ${var_fortiflex_token}
%{ endif ~}
--==FORTIANALYZER-BOOTSTRAP==--
