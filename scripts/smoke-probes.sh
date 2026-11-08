# shellcheck shell=bash
# Koel：sso=none——登录用应用自己的邮箱账号。init 服务把上游写死的默认管理员（admin@koel.dev /
# KoelIsCool）的登录邮箱改成主人的内部邮箱，身份探测就用内部邮箱登录；密码默认 KoelIsCool。
# 网页和应用接口都经核心网关（请求要带用户会话）；应用自己的接口再加 Koel 的 Bearer 令牌。

web_assert() { grep -qi 'koel'; }   # 标准输入：SPA 首页 HTML

koel_login() { # 登录主人账号，输出 Bearer 令牌
  local resp
  resp="$(curl -sS --noproxy '*' -b "$SMOKE_JAR" -H 'Content-Type: application/json' \
    -d "{\"email\":\"$WONTON_OWNER_EMAIL\",\"password\":\"KoelIsCool\"}" "$SMOKE_WEB_URL/api/me")" ||
    { echo "登录请求失败"; return 1; }
  local token
  token="$(jq -r '.token // empty' <<<"$resp")"
  [[ -n "$token" ]] || { echo "登录没有返回 token：$resp"; return 1; }
  printf '%s' "$token"
}

identity_check() { # 应用自己的当前用户接口：认出的是管理员
  local token me
  token="$(koel_login)" || return 1
  me="$(curl -sS --noproxy '*' -b "$SMOKE_JAR" -H "Authorization: Bearer $token" -H 'Accept: application/json' \
    "$SMOKE_WEB_URL/api/me")" || { echo "GET /api/me 失败：$me"; return 1; }
  jq -e '.is_admin == true and .role == "admin"' <<<"$me" >/dev/null ||
    { echo "当前用户不是管理员：$me"; return 1; }
}

data_write() { # 建一个带随机标记的歌单，把标记原样写进 $SMOKE_STATE（覆盖写）
  local token resp marker
  marker="wonton-smoke-$(date +%s)-$RANDOM"
  token="$(koel_login)" || return 1
  resp="$(curl -sS --noproxy '*' -b "$SMOKE_JAR" -H "Authorization: Bearer $token" -H 'Content-Type: application/json' \
    -d "{\"name\":\"$marker\"}" "$SMOKE_WEB_URL/api/playlists")" || { echo "建歌单失败：$resp"; return 1; }
  jq -e --arg m "$marker" '(if type == "object" and has("data") then .data else . end).name == $m' <<<"$resp" >/dev/null ||
    { echo "建歌单回显对不上：$resp"; return 1; }
  printf '%s' "$marker" > "$SMOKE_STATE"
}

data_check() { # 从 $SMOKE_STATE 读回标记，去应用里找回带标记的歌单
  local token playlists marker
  marker="$(cat "$SMOKE_STATE" 2>/dev/null)"
  [[ -n "$marker" ]] || { echo "没有标记或标记为空"; return 1; }
  token="$(koel_login)" || return 1
  playlists="$(curl -sS --noproxy '*' -b "$SMOKE_JAR" -H "Authorization: Bearer $token" -H 'Accept: application/json' \
    "$SMOKE_WEB_URL/api/playlists")" || { echo "列歌单失败：$playlists"; return 1; }
  jq -e --arg m "$marker" '(if type == "array" then . else (.data // [.]) end) | map(.name) | index($m)' <<<"$playlists" >/dev/null ||
    { echo "歌单里找不到标记 $marker：$(head -c 300 <<<"$playlists")"; return 1; }
}
