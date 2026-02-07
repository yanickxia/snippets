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

non_interactive=0
master_password=""
item_cli=""
output_cli=""
kind_cli=""

while getopts "ni:p:o:k:" opt; do
	case "$opt" in
		n) non_interactive=1 ;;
		i) item_cli="$OPTARG" ;;
		p) master_password="$OPTARG" ;;
		o) output_cli="$OPTARG" ;;
		k) kind_cli="$OPTARG" ;;
	esac
done

command_exists bw || die "bw CLI not found. Install it first."

status="$(bw status 2>/dev/null | tr -d ' \n')"
case "$status" in
	*'"status":"unauthenticated"'*)
		if [ "$non_interactive" -eq 1 ]; then
			die "bw 未登录，请先执行 bw login"
		else
			echo "Bitwarden 未登录，开始登录"
			printf "邮箱 (直接回车进入交互式登录): "
			read -r bw_email || bw_email=""
			if [ -n "$bw_email" ]; then
				bw login "$bw_email" || die "登录失败"
			else
				bw login || die "登录失败"
			fi
			status="$(bw status 2>/dev/null | tr -d ' \n')"
		fi
		;;
	*'"status":"locked"'*)
		if [ -z "${BW_SESSION:-}" ]; then
			if [ "$non_interactive" -eq 1 ]; then
				[ -n "$master_password" ] || die "缺少密码参数 (-p)"
				BW_SESSION="$(bw unlock --raw "$master_password" 2>/dev/null || true)"
				if [ -z "$BW_SESSION" ]; then
					BW_SESSION="$(bw unlock "$master_password" --raw 2>/dev/null || true)"
				fi
				if [ -z "$BW_SESSION" ]; then
					BW_SESSION="$(printf '%s' "$master_password" | bw unlock --raw 2>/dev/null || true)"
				fi
				[ -n "$BW_SESSION" ] || die "解锁失败，请检查密码"
			else
				BW_SESSION="$(bw unlock --raw)"
				[ -n "$BW_SESSION" ] || die "failed to unlock vault"
			fi
			export BW_SESSION
		fi
		;;
	*'"status":"unlocked"'*)
		if [ -z "${BW_SESSION:-}" ]; then
			if [ "$non_interactive" -eq 1 ]; then
				[ -n "$master_password" ] || die "缺少密码参数 (-p)"
				BW_SESSION="$(bw unlock --raw "$master_password" 2>/dev/null || true)"
				if [ -z "$BW_SESSION" ]; then
					BW_SESSION="$(bw unlock "$master_password" --raw 2>/dev/null || true)"
				fi
				if [ -z "$BW_SESSION" ]; then
					BW_SESSION="$(printf '%s' "$master_password" | bw unlock --raw 2>/dev/null || true)"
				fi
				[ -n "$BW_SESSION" ] || die "解锁失败，请检查密码"
			else
				BW_SESSION="$(bw unlock --raw)"
				[ -n "$BW_SESSION" ] || die "failed to get session token"
			fi
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

if [ -n "$item_cli" ]; then
	item="$item_cli"
else
	printf "请输入 Bitwarden 项目名称或ID: "
	read -r item || die "未输入项目名称或ID"
	[ -n "$item" ] || die "未输入项目名称或ID"
fi

default_output="$HOME/.ssh/id_rsa"
if [ -n "$output_cli" ]; then
	output="$(expand_path "$output_cli")"
else
	if [ "$non_interactive" -eq 1 ]; then
		output="$default_output"
	else
		printf "保存路径 [默认: %s]: " "$default_output"
		read -r output_path || output_path=""
		if [ -z "$output_path" ]; then
			output="$default_output"
		else
			output="$(expand_path "$output_path")"
		fi
	fi
fi

item_json="$(bw get item "$item" 2>/dev/null || true)"
if [ -z "$item_json" ]; then
	items_json="$(bw list items --search "$item")" || die "无法搜索到条目: $item"
	count="$(printf '%s' "$items_json" | "$py_cmd" -c 'import json,sys; a=json.load(sys.stdin); print(len(a))')"
	[ "$count" -gt 0 ] || die "未找到匹配条目: $item"
	if [ "$count" -gt 1 ]; then
		printf '%s' "$items_json" | "$py_cmd" -c 'import json,sys; a=json.load(sys.stdin); [print(f"{i+1}) {it.get(\"name\",\"\")}\t{it.get(\"id\",\"\")}") for i,it in enumerate(a)]'
		printf "选择条目编号: "
		read -r sel || die "未选择条目"
		item_id="$(printf '%s' "$items_json" | "$py_cmd" -c 'import json,sys; a=json.load(sys.stdin); import sys; idx=int(sys.argv[1])-1; print(a[idx].get("id","") if 0<=idx<len(a) else "")' "$sel")"
		[ -n "$item_id" ] || die "选择无效"
	else
		item_id="$(printf '%s' "$items_json" | "$py_cmd" -c 'import json,sys; a=json.load(sys.stdin); print(a[0].get("id",""))')"
	fi
	item_json="$(bw get item "$item_id")" || die "获取条目失败"
else
	item_id="$(printf '%s' "$item_json" | "$py_cmd" -c 'import json,sys; print(json.load(sys.stdin).get("id",""))')"
fi
[ -n "$item_id" ] || die "无法解析条目 ID"

output_dir="$(dirname "$output")"
mkdir -p "$output_dir"

if [ -e "$output" ]; then
	if [ "$non_interactive" -eq 1 ]; then
		:
	else
		printf "%s 已存在，是否覆盖? [y/N]: " "$output"
		read -r overwrite || overwrite=""
		case "$overwrite" in
			y|Y) ;;
			*) die "已取消" ;;
		esac
	fi
fi

umask 077

ssh_private="$(printf '%s' "$item_json" | "$py_cmd" -c 'import json,sys; d=json.load(sys.stdin); print(d.get("sshKey",{}).get("privateKey",""))')"
ssh_public="$(printf '%s' "$item_json" | "$py_cmd" -c 'import json,sys; d=json.load(sys.stdin); print(d.get("sshKey",{}).get("publicKey",""))')"

if [ -n "$ssh_private" ] || [ -n "$ssh_public" ]; then
	if [ "$non_interactive" -eq 1 ]; then
		kind="${kind_cli:-a}"
	else
		printf "保存内容选择 [p=私钥, P=公钥, a=全部，默认 a]: "
		read -r kind || kind=""
		if [ -z "$kind" ]; then
			kind="a"
		fi
	fi
	case "$kind" in
		P)
			[ -n "$ssh_public" ] || die "该条目不含公钥"
			if [ "$output" = "$HOME/.ssh/id_rsa" ]; then
				output="$HOME/.ssh/id_rsa.pub"
			fi
			if [ -e "$output" ]; then
				if [ "$non_interactive" -eq 1 ]; then
					:
				else
					printf "%s 已存在，是否覆盖? [y/N]: " "$output"
					read -r overwrite_pub || overwrite_pub=""
					case "$overwrite_pub" in
						y|Y) ;;
						*) die "已取消" ;;
					esac
				fi
			fi
			printf '%s\n' "$ssh_public" > "$output"
			;;
		a)
			if [ "$output" = "$HOME/.ssh/id_rsa" ]; then
				private_path="$HOME/.ssh/id_rsa"
				pub_path="$HOME/.ssh/id_rsa.pub"
			else
				case "$output" in
					*.pub)
						pub_path="$output"
						private_path="${output%*.pub}"
						;;
					*)
						private_path="$output"
						pub_path="$output.pub"
						;;
				esac
			fi
			[ -n "$ssh_private" ] || die "该条目不含私钥"
			[ -n "$ssh_public" ] || die "该条目不含公钥"
			if [ -e "$private_path" ] || [ -e "$pub_path" ]; then
				if [ "$non_interactive" -eq 1 ]; then
					:
				else
					printf "%s 或 %s 已存在，是否覆盖? [y/N]: " "$private_path" "$pub_path"
					read -r overwrite_both || overwrite_both=""
					case "$overwrite_both" in
						y|Y) ;;
						*) die "已取消" ;;
					esac
				fi
			fi
			printf '%s\n' "$ssh_private" > "$private_path"
			printf '%s\n' "$ssh_public" > "$pub_path"
			;;
		*)
			[ -n "$ssh_private" ] || die "该条目不含私钥"
			printf '%s\n' "$ssh_private" > "$output"
			;;
	esac
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
		die "该 Item 不包含 sshKey 字段或附件"
	fi
fi

if [ "$kind" = "a" ]; then
	chmod 0600 "$private_path"
	chmod 0644 "$pub_path"
	echo "已保存到 $private_path 和 $pub_path"
else
	case "$output" in
		*.pub) chmod 0644 "$output" ;;
		*) chmod 0600 "$output" ;;
	esac
	echo "已保存到 $output"
fi
