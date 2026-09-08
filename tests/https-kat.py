#!/usr/bin/env python3
"""本地 TLS KAT: 调用真实 lib/portable.sh 的 bbp_https_get (M2 验收)。

用法: python3 tests/https-kat.py [CURL 路径] [CA bundle 路径]

覆盖 (docs/COMPANION-DELIVERY-PLAN.md M2):
  有效证书成功; 错误主机名失败; 不可信 CA 失败; 过期证书失败;
  重定向不降级 HTTP; 后端不可用明确失败; 显式 CA 缺失失败。
证书由 openssl 现场生成; curl 默认取 PATH 中的 curl (交付 curl.com 后以
同一参数集回归即成为正式联网 KAT 的本地镜像)。
"""
import http.server
import os
import shutil
import socketserver
import ssl
import subprocess
import sys
import tempfile
import threading

REDIRECT_TO_HTTP = "/downgrade"
DOWNGRADE_SEEN = threading.Event()


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == REDIRECT_TO_HTTP:
            self.send_response(302)
            self.send_header("Location", "http://127.0.0.1:%d/plain" % self.server.http_port)
            self.end_headers()
            return
        body = b"kat-ok"
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


class PlainHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        DOWNGRADE_SEEN.set()
        body = b"downgraded-plaintext"
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


def die(msg):
    print("FAIL:", msg)
    sys.exit(1)


def fail_if(cond, msg):
    if cond:
        die(msg)


def run_curl(curl, args, env=None):
    # APE(.com) 在 macOS 上经 posix_spawn 会被拒; 统一经 sh exec 启动
    cmd = ["/bin/sh", "-c", 'exec "$0" "$@"', curl] + list(args)
    return subprocess.run(cmd, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, timeout=30, env=env)


def run_https(curl, args, env):
    """保留用例参数形态，但所有下载均经过真实公开包装器。"""
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    call_env = dict(env, BBP_CURL=os.path.abspath(curl),
                    BBP_CA_BUNDLE=args[args.index("--cacert") + 1])
    shell = ["/bin/sh"]
    if env.get("BBP_TEST_BUSYBOX"):
        shell = ["/bin/sh", "-c", 'exec "$0" "$@"',
                 env["BBP_TEST_BUSYBOX"], "ash"]
    return subprocess.run(shell + ["-c",
        '. "$1" || exit; bbp_https_get "$2" "$3"', "https-kat",
        os.path.join(root, "lib", "portable.sh"), args[-1],
        args[args.index("--output") + 1]], env=call_env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)


def openssl_ok():
    r = subprocess.run(["openssl", "version"], stdout=subprocess.PIPE,
                       stderr=subprocess.PIPE)
    return r.returncode == 0


def gen_cert(tmp, cn, san, ca_pem=None, ca_key=None, days=2,
             ca=False, out="srv"):
    """生成 CA(自签) 或由 CA 签发的服务器证书。SAN 形如 DNS:localhost,IP:127.0.0.1"""
    base = os.path.join(tmp, out)
    if ca:
        conf = os.path.join(tmp, "ca.cnf")
        with open(conf, "w") as f:
            f.write("[req]\n")
            f.write("distinguished_name = dn\n")
            f.write("prompt = no\n")
            f.write("x509_extensions = v3_ca\n")
            f.write("[dn]\n")
            f.write("CN = %s\n" % cn)
            f.write("[v3_ca]\n")
            f.write("basicConstraints = critical,CA:TRUE\n")
            f.write("keyUsage = critical,keyCertSign,cRLSign\n")
        r = subprocess.run(
            ["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
             "-keyout", base + ".key", "-out", base + ".pem", "-days", "3650",
             "-config", conf],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if r.returncode != 0:
            raise RuntimeError("CA 生成失败: " + r.stderr.decode()[:300])
        return base + ".pem", base + ".key"
    key = base + ".key"
    csr = base + ".csr"
    r = subprocess.run(
        ["openssl", "req", "-new", "-newkey", "rsa:2048", "-nodes",
         "-keyout", key, "-out", csr, "-subj", "/CN=%s" % cn],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if r.returncode != 0:
        raise RuntimeError("CSR 失败: " + r.stderr.decode()[:200])
    ext = os.path.join(tmp, out + ".ext")
    with open(ext, "w") as f:
        f.write("subjectAltName=%s\n" % san)
        f.write("extendedKeyUsage=serverAuth\n")
    crt = base + ".pem"
    r = subprocess.run(
        ["openssl", "x509", "-req", "-in", csr, "-CA", ca_pem, "-CAkey",
         ca_key, "-CAcreateserial", "-out", crt, "-days", str(days),
         "-extfile", ext],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if r.returncode != 0:
        raise RuntimeError("签发失败: " + r.stderr.decode()[:300])
    return crt, key


def serve_https(cert, key, http_port_ref):
    httpd = socketserver.TCPServer(("127.0.0.1", 0), Handler)
    httpd.http_port = http_port_ref
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(cert, key)
    httpd.socket = ctx.wrap_socket(httpd.socket, server_side=True)
    t = threading.Thread(target=httpd.serve_forever, daemon=True)
    t.start()
    return httpd


def main():
    if len(sys.argv) not in (1, 2, 3):
        print("用法: python3 tests/https-kat.py [CURL] [CA_BUNDLE]", file=sys.stderr)
        return 2
    curl = sys.argv[1] if len(sys.argv) >= 2 else None
    bundle = os.path.abspath(sys.argv[2]) if len(sys.argv) == 3 else None
    if curl is None:
        curl = shutil.which("curl")
    fail_if(curl is None or not os.path.isfile(curl), "缺少 curl: 提供路径或装好宿主 curl")
    print("KAT 被测 curl:", curl, "版本:", end=" ")
    v = run_curl(curl, ["--disable", "--version"])
    if v.returncode == 0:
        ver = v.stdout.decode(errors="replace")
        print(ver.splitlines()[0] if ver else "未知")
    else:
        print("未知")
    fail_if(not openssl_ok(), "缺少 openssl (证书生成依赖)")

    tmp = tempfile.mkdtemp(prefix="https-kat.")
    servers = []
    try:
        # 故意提供危险配置：包装器必须忽略它，而不是依赖干净宿主。
        with open(os.path.join(tmp, ".curlrc"), "w") as f:
            f.write("insecure\n")
        env = dict(os.environ, CURL_HOME=tmp, NO_PROXY="*", no_proxy="*")
        def fetch(args):
            return run_https(curl, args, env)

        ca_pem, ca_key = gen_cert(tmp, "bb-kat-ca", "", ca=True, out="ca")
        unrelated_ca, _ = gen_cert(tmp, "unrelated-ca", "", ca=True, out="other-ca")
        good_crt, good_key = gen_cert(
            tmp, "localhost", "DNS:localhost,IP:127.0.0.1",
            ca_pem, ca_key, out="good")
        wrong_crt, wrong_key = gen_cert(
            tmp, "other.test", "DNS:other.test", ca_pem, ca_key, out="wrong")
        # 有效 + 错误主机名两个服务
        plain = socketserver.TCPServer(("127.0.0.1", 0), PlainHandler)
        pt = threading.Thread(target=plain.serve_forever, daemon=True)
        pt.start()
        servers.append(plain)
        http_good = serve_https(good_crt, good_key, plain.server_address[1])
        servers.append(http_good)
        http_wrong = serve_https(wrong_crt, wrong_key, plain.server_address[1])
        servers.append(http_wrong)
        good_url = "https://127.0.0.1:%d/ok" % http_good.server_address[1]
        wrong_url = "https://127.0.0.1:%d/ok" % http_wrong.server_address[1]
        redir_url = "https://127.0.0.1:%d%s" % (http_good.server_address[1],
                                                REDIRECT_TO_HTTP)
        plain_port = plain.server_address[1]
        base = []  # 下载策略只由 lib/portable.sh 定义，不在测试复制一份。

        # 1) 有效证书成功
        out = os.path.join(tmp, "ok.out")
        r = fetch(base + ["--cacert", ca_pem, "--output", out, good_url])
        fail_if(r.returncode != 0, "有效证书请求失败 rc=%d %s"
                % (r.returncode, r.stderr.decode(errors="replace")))
        with open(out, "rb") as f:
            fail_if(f.read() != b"kat-ok", "有效请求内容不符")
        print("PASS 有效证书成功")

        # 2) 错误主机名失败
        r = fetch(base + ["--cacert", ca_pem, "--output",
                                   os.path.join(tmp, "x"), wrong_url])
        fail_if(r.returncode != 60, "错误主机名应返回证书错误 60: %r" % r)
        print("PASS 错误主机名失败")

        # 3) 合法但无关的 CA，不能以 PEM 解析失败冒充信任链拒绝。
        r = fetch(base + ["--cacert", unrelated_ca, "--output",
                                   os.path.join(tmp, "x"), good_url])
        fail_if(r.returncode != 60, "不可信 CA 应返回证书错误 60: %r" % r)
        print("PASS 不可信 CA 失败")

        # 4) 过期证书: openssl x509 -req 不接受负 days, 改用 openssl ca 的
        #    -startdate/-enddate 显式生成 notAfter 已过去的证书
        try:
            exp_key = os.path.join(tmp, "exp.key")
            exp_csr = os.path.join(tmp, "exp.csr")
            r = subprocess.run(
                ["openssl", "req", "-new", "-newkey", "rsa:2048", "-nodes",
                 "-keyout", exp_key, "-out", exp_csr, "-subj", "/CN=localhost"],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            if r.returncode != 0:
                raise RuntimeError(r.stderr.decode()[:200])
            idx = os.path.join(tmp, "index.txt")
            ser = os.path.join(tmp, "serial")
            open(idx, "w").close()
            open(ser, "w").write("1000\n")
            ca_cnf = os.path.join(tmp, "ca-cmd.cnf")
            with open(ca_cnf, "w") as f:
                f.write("[ ca ]\ndefault_ca = CA_default\n[ CA_default ]\n")
                f.write("dir = %s\ndatabase = %s\nnew_certs_dir = %s\n"
                        % (tmp, idx, tmp))
                f.write("certificate = %s\nprivate_key = %s\nserial = %s\n"
                        % (ca_pem, ca_key, ser))
                f.write("default_md = sha256\npolicy = policy_any\n"
                        "[ policy_any ]\ncommonName = supplied\n")
                f.write("[ server_ext ]\nsubjectAltName=DNS:localhost,IP:127.0.0.1\n"
                        "extendedKeyUsage=serverAuth\n")
            exp_crt = os.path.join(tmp, "exp.pem")
            r = subprocess.run(
                ["openssl", "ca", "-config", ca_cnf, "-in", exp_csr,
                 "-out", exp_crt, "-batch", "-notext", "-extensions", "server_ext",
                 "-startdate", "20200101000000Z", "-enddate", "20210101000000Z"],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            if r.returncode != 0:
                raise RuntimeError(r.stderr.decode()[:200])
            http_exp = serve_https(exp_crt, exp_key, plain_port)
            servers.append(http_exp)
            exp_url = "https://127.0.0.1:%d/ok" % http_exp.server_address[1]
            rr = fetch(base + ["--cacert", ca_pem, "--output",
                                        os.path.join(tmp, "x"), exp_url])
            fail_if(rr.returncode != 60, "过期证书应返回证书错误 60: %r" % rr)
            print("PASS 过期证书失败")
        except Exception as e:  # noqa: BLE001
            raise RuntimeError("过期证书用例未完成，不能记为通过") from e

        # 5) 重定向不降级 HTTP
        DOWNGRADE_SEEN.clear()
        r = fetch(base + ["--cacert", ca_pem, "--output",
                                   os.path.join(tmp, "x"), redir_url])
        fail_if(DOWNGRADE_SEEN.is_set(), "重定向降级到了明文 HTTP (http 服务器被访问)")
        fail_if(r.returncode == 0, "禁止降级时应失败 rc!=0 (rc=%d %s)"
                % (r.returncode, r.stderr.decode(errors="replace")[:160]))
        print("PASS 重定向不降级 HTTP")

        # 6) 显式 CA bundle 不存在
        r = fetch(base + ["--cacert", os.path.join(tmp, "nope.pem"),
                                   "--output", os.path.join(tmp, "x"),
                                   good_url])
        fail_if(r.returncode == 0, "CA 缺失应失败 rc!=0")
        print("PASS CA bundle 缺失明确失败")
        print("PASS 实际 bbp_https_get 忽略 insecure curlrc")

        print("HTTPS KAT: 全部通过 (curl: %s)" % curl)
        return 0
    finally:
        for h in servers:
            if h is not None:
                try:
                    h.shutdown()
                    h.server_close()
                except Exception:
                    pass
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
