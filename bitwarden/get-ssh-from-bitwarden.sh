#!/bin/sh
set -e

command_exists() {
	command -v "$1" >/dev/null 2>&1
}

die() {
	echo "Error: $*" >&2
	exit 1
}

expand_path() {
	case "$1" in
		"~") printf '%s' "$HOME" ;;
		~/*) printf '%s%s' "$HOME" "${1#\~}" ;;
		*) printf '%s' "$1" ;;
	esac
}

command_exists bw || die "bw CLI not found. Install it first."

status="$(bw status 2>/dev/null | tr -d ' \n')"
case "$status" in
	*'"status":"unauthenticated"'*)
		echo "Bitwarden 未登录，开始登录"
		printf "邮箱 (直接回车进入交互式登录): "
		read -r bw_email || bw_email=""
		if [ -n "$bw_email" ]; then
			bw login "$bw_email" || die "登录失败"
		else
			bw login || die "登录失败"
		fi
		status="$(bw status 2>/dev/null | tr -d ' \n')"
		;;
	*'"status":"locked"'*)
		if [ -z "${BW_SESSION:-}" ]; then
			BW_SESSION="$(bw unlock --raw)"
			[ -n "$BW_SESSION" ] || die "failed to unlock vault"
			export BW_SESSION
		fi
		;;
	*'"status":"unlocked"'*)
		if [ -z "${BW_SESSION:-}" ]; then
			BW_SESSION="$(bw unlock --raw)"
			[ -n "$BW_SESSION" ] || die "failed to get session token"
			export BW_SESSION
		fi
		;;
	*)
		echo "Warning: unable to determine bw status." >&2
		;;
esac

if command_exists python3; then
	py_cmd="python3"
elif command_exists python; then
	py_cmd="python"
else
	die "python is required to parse bw output"
fi

printf "请输入 Bitwarden 项目名称或ID: "
read -r item || die "未输入项目名称或ID"
[ -n "$item" ] || die "未输入项目名称或ID"

default_output="$HOME/.ssh/id_rsa"
printf "保存路径 [默认: %s]: " "$default_output"
read -r output_path || output_path=""
if [ -z "$output_path" ]; then
	output="$default_output"
else
	output="$(expand_path "$output_path")"
fi

item_json="$(bw get item "$item")" || die "item not found: $item"
item_id="$(printf '%s' "$item_json" | "$py_cmd" -c 'import json,sys; print(json.load(sys.stdin).get("id",""))')"
[ -n "$item_id" ] || die "unable to resolve item id"

output_dir="$(dirname "$output")"
mkdir -p "$output_dir"

if [ -e "$output" ]; then
	printf "%s 已存在，是否覆盖? [y/N]: " "$output"
	read -r overwrite || overwrite=""
	case "$overwrite" in
		y|Y) ;;
		*) die "已取消" ;;
	esac
fi

umask 077

notes="$(printf '%s' "$item_json" | "$py_cmd" -c 'import json,sys; d=json.load(sys.stdin); n=d.get("notes") or ""; print(n)')"
if [ -n "$notes" ]; then
	printf '%s' "$notes" > "$output"
else
	att_count="$(printf '%s' "$item_json" | "$py_cmd" -c 'import json,sys; d=json.load(sys.stdin); at=d.get("attachments") or []; print(len(at))')"
	if [ "$att_count" -gt 0 ]; then
		if [ "$att_count" -eq 1 ]; then
			attachment_id="$(printf '%s' "$item_json" | "$py_cmd" -c 'import json,sys; d=json.load(sys.stdin); at=d.get("attachments") or []; print(at[0].get("id",""))')"
			[ -n "$attachment_id" ] || die "无法解析附件"
			bw get attachment "$attachment_id" --itemid "$item_id" --output "$output"
		else
			echo "检测到多个附件："
			printf '%s' "$item_json" | "$py_cmd" -c 'import json,sys; d=json.load(sys.stdin); at=d.get("attachments") or []; [print(f"{i+1}) {a.get(\"fileName\",\"\")}") for i,a in enumerate(at)]'
			printf "选择要下载的编号: "
			read -r sel || die "未选择附件"
			attachment_id="$(printf '%s' "$item_json" | "$py_cmd" -c 'import json,sys; d=json.load(sys.stdin); at=d.get("attachments") or []; import sys; idx=int(sys.argv[1])-1; print(at[idx].get("id","") if 0<=idx<len(at) else "")' "$sel")"
			[ -n "$attachment_id" ] || die "选择无效"
			bw get attachment "$attachment_id" --itemid "$item_id" --output "$output"
		fi
	else
		die "该 Item 不包含 notes 或附件"
	fi
fi

case "$output" in
	*.pub) chmod 0644 "$output" ;;
	*) chmod 0600 "$output" ;;
esac

echo "已保存到 $output"
