###############################################################################
# FortiGate — Local Users
###############################################################################

resource "fortios_user_local" "user" {
  for_each = local.fgt_local_users

  name   = each.key
  type   = each.value.type
  passwd = each.value.password
  status = "enable"
}

###############################################################################
# FortiGate — User Groups
###############################################################################

resource "fortios_user_group" "group" {
  for_each = local.fgt_user_groups

  name = each.key

  dynamic "member" {
    for_each = each.value.members
    content {
      name = member.value
    }
  }

  depends_on = [fortios_user_local.user]
}
