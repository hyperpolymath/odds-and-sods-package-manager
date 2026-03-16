// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// QUIC/HTTP3 transport NIF for OPSM.
// Uses quinn (QUIC) + h3 (HTTP/3) to provide fast registry fetches.

#![forbid(unsafe_code)]
use rustler::{Atom, Binary, Encoder, Env, NifResult, OwnedBinary, ResourceArc, Term};
use std::net::ToSocketAddrs;
use std::sync::Arc;
use std::time::Duration;
use tokio::runtime::Runtime;

mod atoms {
    rustler::atoms! {
        ok,
        error,
        nif_loaded,
        timeout,
        connection_failed,
        handshake_failed,
        request_failed,
        invalid_host,
    }
}

/// Opaque QUIC connection handle passed to Elixir.
struct QuicConnection {
    endpoint: quinn::Endpoint,
    connection: quinn::Connection,
    runtime: Arc<Runtime>,
}

/// Register the QuicConnection as a NIF resource.
fn on_load(env: Env, _info: Term) -> bool {
    rustler::resource!(QuicConnection, env);
    true
}

/// Check if the NIF is loaded.
#[rustler::nif]
fn nif_loaded() -> bool {
    true
}

/// Probe whether a host supports QUIC.
/// Attempts a QUIC handshake and returns true/false.
#[rustler::nif(schedule = "DirtyCpu")]
fn probe(host: String, port: u16, timeout_ms: u64) -> NifResult<(Atom, bool)> {
    let rt = Runtime::new().map_err(|e| rustler::Error::Term(Box::new(format!("{}", e))))?;

    let result = rt.block_on(async {
        let addr = format!("{}:{}", host, port)
            .to_socket_addrs()
            .map_err(|_| "invalid_host")?
            .next()
            .ok_or("invalid_host")?;

        let crypto = rustls::ClientConfig::builder()
            .with_webpki_verifier(
                rustls::client::WebPkiServerVerifier::builder(Arc::new(
                    rustls::RootCertStore::from_iter(webpki_roots::TLS_SERVER_ROOTS.iter().cloned()),
                ))
                .build()
                .map_err(|e| format!("{}", e))?,
            )
            .with_no_client_auth();

        let client_config =
            quinn::ClientConfig::new(Arc::new(quinn::crypto::rustls::QuicClientConfig::try_from(crypto).map_err(|e| format!("{}", e))?));

        let mut endpoint = quinn::Endpoint::client("0.0.0.0:0".parse().unwrap())
            .map_err(|e| format!("{}", e))?;
        endpoint.set_default_client_config(client_config);

        let connect = endpoint.connect(addr, &host).map_err(|e| format!("{}", e))?;

        match tokio::time::timeout(Duration::from_millis(timeout_ms), connect).await {
            Ok(Ok(conn)) => {
                conn.close(0u32.into(), b"probe");
                endpoint.wait_idle().await;
                Ok(true)
            }
            Ok(Err(_)) => Ok(false),
            Err(_) => Ok(false),
        }
    });

    match result {
        Ok(supported) => Ok((atoms::ok(), supported)),
        Err(_) => Ok((atoms::ok(), false)),
    }
}

/// Open a QUIC connection to host:port.
#[rustler::nif(schedule = "DirtyCpu")]
fn connect<'a>(
    env: Env<'a>,
    host: String,
    port: u16,
    timeout_ms: u64,
) -> NifResult<Term<'a>> {
    let rt = Arc::new(
        Runtime::new().map_err(|e| rustler::Error::Term(Box::new(format!("{}", e))))?,
    );

    let rt_clone = rt.clone();
    let result = rt.block_on(async {
        let addr = format!("{}:{}", host, port)
            .to_socket_addrs()
            .map_err(|_| "invalid_host")?
            .next()
            .ok_or("invalid_host")?;

        let crypto = rustls::ClientConfig::builder()
            .with_webpki_verifier(
                rustls::client::WebPkiServerVerifier::builder(Arc::new(
                    rustls::RootCertStore::from_iter(webpki_roots::TLS_SERVER_ROOTS.iter().cloned()),
                ))
                .build()
                .map_err(|e| format!("{}", e))?,
            )
            .with_no_client_auth();

        let client_config =
            quinn::ClientConfig::new(Arc::new(quinn::crypto::rustls::QuicClientConfig::try_from(crypto).map_err(|e| format!("{}", e))?));

        let mut endpoint = quinn::Endpoint::client("0.0.0.0:0".parse().unwrap())
            .map_err(|e| format!("{}", e))?;
        endpoint.set_default_client_config(client_config);

        let connect = endpoint.connect(addr, &host).map_err(|e| format!("{}", e))?;

        match tokio::time::timeout(Duration::from_millis(timeout_ms), connect).await {
            Ok(Ok(conn)) => Ok((endpoint, conn)),
            Ok(Err(e)) => Err(format!("handshake_failed: {}", e)),
            Err(_) => Err("timeout".to_string()),
        }
    });

    match result {
        Ok((endpoint, connection)) => {
            let resource = ResourceArc::new(QuicConnection {
                endpoint,
                connection,
                runtime: rt_clone,
            });
            Ok((atoms::ok(), resource).encode(env))
        }
        Err(msg) => Ok((atoms::error(), msg).encode(env)),
    }
}

/// Send an HTTP/3 GET request over a QUIC connection.
#[rustler::nif(schedule = "DirtyCpu")]
fn h3_get<'a>(
    env: Env<'a>,
    conn: ResourceArc<QuicConnection>,
    path: String,
    _headers: Vec<(String, String)>,
) -> NifResult<Term<'a>> {
    let result = conn.runtime.block_on(async {
        let quinn_conn = conn.connection.clone();
        let h3_conn = h3_quinn::Connection::new(quinn_conn);
        let (mut driver, mut send_request) = h3::client::new(h3_conn)
            .await
            .map_err(|e| format!("h3 init: {}", e))?;

        // Drive the connection in background
        tokio::spawn(async move {
            let _ = futures_util::future::poll_fn(|cx| driver.poll_close(cx)).await;
        });

        let req = http::Request::builder()
            .method("GET")
            .uri(&path)
            .header("user-agent", "opsm/1.2.0")
            .body(())
            .map_err(|e| format!("build request: {}", e))?;

        let mut stream = send_request
            .send_request(req)
            .await
            .map_err(|e| format!("send: {}", e))?;

        stream.finish().await.map_err(|e| format!("finish: {}", e))?;

        let resp = stream
            .recv_response()
            .await
            .map_err(|e| format!("recv response: {}", e))?;

        let status = resp.status().as_u16();
        let headers: Vec<(String, String)> = resp
            .headers()
            .iter()
            .map(|(k, v)| (k.to_string(), v.to_str().unwrap_or("").to_string()))
            .collect();

        // Collect body
        let mut body = Vec::new();
        while let Some(chunk) = stream
            .recv_data()
            .await
            .map_err(|e| format!("recv body: {}", e))?
        {
            body.extend_from_slice(&chunk);
        }

        Ok::<_, String>((status, headers, body))
    });

    match result {
        Ok((status, headers, body)) => {
            let mut bin = OwnedBinary::new(body.len()).unwrap();
            bin.as_mut_slice().copy_from_slice(&body);
            let binary = Binary::from_owned(bin, env);
            Ok((atoms::ok(), (status, headers, binary)).encode(env))
        }
        Err(msg) => Ok((atoms::error(), msg).encode(env)),
    }
}

/// Send an HTTP/3 POST request over a QUIC connection.
#[rustler::nif(schedule = "DirtyCpu")]
fn h3_post<'a>(
    env: Env<'a>,
    conn: ResourceArc<QuicConnection>,
    path: String,
    req_body: Binary,
    _headers: Vec<(String, String)>,
) -> NifResult<Term<'a>> {
    let body_bytes = req_body.as_slice().to_vec();

    let result = conn.runtime.block_on(async {
        let quinn_conn = conn.connection.clone();
        let h3_conn = h3_quinn::Connection::new(quinn_conn);
        let (mut driver, mut send_request) = h3::client::new(h3_conn)
            .await
            .map_err(|e| format!("h3 init: {}", e))?;

        tokio::spawn(async move {
            let _ = futures_util::future::poll_fn(|cx| driver.poll_close(cx)).await;
        });

        let req = http::Request::builder()
            .method("POST")
            .uri(&path)
            .header("content-type", "application/json")
            .header("user-agent", "opsm/1.2.0")
            .body(())
            .map_err(|e| format!("build request: {}", e))?;

        let mut stream = send_request
            .send_request(req)
            .await
            .map_err(|e| format!("send: {}", e))?;

        stream
            .send_data(bytes::Bytes::from(body_bytes))
            .await
            .map_err(|e| format!("send body: {}", e))?;

        stream.finish().await.map_err(|e| format!("finish: {}", e))?;

        let resp = stream
            .recv_response()
            .await
            .map_err(|e| format!("recv response: {}", e))?;

        let status = resp.status().as_u16();
        let headers: Vec<(String, String)> = resp
            .headers()
            .iter()
            .map(|(k, v)| (k.to_string(), v.to_str().unwrap_or("").to_string()))
            .collect();

        let mut body = Vec::new();
        while let Some(chunk) = stream
            .recv_data()
            .await
            .map_err(|e| format!("recv body: {}", e))?
        {
            body.extend_from_slice(&chunk);
        }

        Ok::<_, String>((status, headers, body))
    });

    match result {
        Ok((status, headers, body)) => {
            let mut bin = OwnedBinary::new(body.len()).unwrap();
            bin.as_mut_slice().copy_from_slice(&body);
            let binary = Binary::from_owned(bin, env);
            Ok((atoms::ok(), (status, headers, binary)).encode(env))
        }
        Err(msg) => Ok((atoms::error(), msg).encode(env)),
    }
}

/// Close a QUIC connection.
#[rustler::nif]
fn close(conn: ResourceArc<QuicConnection>) -> Atom {
    conn.connection.close(0u32.into(), b"done");
    atoms::ok()
}

/// Get connection statistics.
#[rustler::nif]
fn connection_stats<'a>(
    env: Env<'a>,
    conn: ResourceArc<QuicConnection>,
) -> NifResult<Term<'a>> {
    let stats = conn.connection.stats();
    let rtt_ms = stats.path.rtt.as_millis() as u64;

    let map = rustler::types::map::map_new(env);
    let map = map.map_put(
        rustler::types::atom::Atom::from_str(env, "rtt_ms").unwrap().encode(env),
        rtt_ms.encode(env),
    ).unwrap();
    let map = map.map_put(
        rustler::types::atom::Atom::from_str(env, "cwnd").unwrap().encode(env),
        stats.path.cwnd.encode(env),
    ).unwrap();
    let map = map.map_put(
        rustler::types::atom::Atom::from_str(env, "lost_packets").unwrap().encode(env),
        stats.path.lost_packets.encode(env),
    ).unwrap();
    let map = map.map_put(
        rustler::types::atom::Atom::from_str(env, "sent_packets").unwrap().encode(env),
        stats.path.sent_packets.encode(env),
    ).unwrap();

    Ok((atoms::ok(), map).encode(env))
}

/// 0-RTT reconnection (stub — full implementation requires session ticket caching).
#[rustler::nif(schedule = "DirtyCpu")]
fn connect_0rtt<'a>(
    env: Env<'a>,
    _host: String,
    _port: u16,
    _session_ticket: Term<'a>,
) -> NifResult<Term<'a>> {
    // 0-RTT requires session ticket from previous connection.
    // For now, signal that 0-RTT is not available so caller does full handshake.
    Ok((atoms::error(), "0rtt_not_available").encode(env))
}

rustler::init!("Elixir.Opsm.Transport.QuicNif", [
    nif_loaded,
    probe,
    connect,
    h3_get,
    h3_post,
    close,
    connection_stats,
    connect_0rtt,
]);
