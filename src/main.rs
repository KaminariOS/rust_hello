use std::{fs, time::Duration};

use axum::{Router, extract::State, response::Html, routing::get};
use chrono::Utc;
use humantime::format_duration;
use k8s_openapi::api::core::v1::{Endpoints, Service};
use kube::{Client, Error as KubeError, api::Api};

#[derive(Clone)]
struct AppState {
    client: Option<Client>,
    client_error: Option<String>,
    namespace: String,
    service_name: String,
}

async fn service_uptime(State(state): State<AppState>) -> Html<String> {
    match &state.client {
        Some(client) => {
            let services: Api<Service> = Api::namespaced(client.clone(), &state.namespace);
            match services.get(&state.service_name).await {
                Ok(svc) => match svc.metadata.creation_timestamp.clone() {
                    Some(ts) => {
                        let creation_time = ts.0;
                        let now = Utc::now();
                        if now >= creation_time {
                            let uptime = now.signed_duration_since(creation_time);
                            let uptime_std =
                                uptime.to_std().unwrap_or_else(|_| Duration::from_secs(0));
                            let endpoints_api: Api<Endpoints> =
                                Api::namespaced(client.clone(), &state.namespace);
                            let replicas_alive = match endpoints_api.get(&state.service_name).await
                            {
                                Ok(endpoints) => Some(
                                    endpoints
                                        .subsets
                                        .unwrap_or_default()
                                        .iter()
                                        .map(|subset| {
                                            subset
                                                .addresses
                                                .as_ref()
                                                .map(|addresses| addresses.len())
                                                .unwrap_or(0)
                                        })
                                        .sum::<usize>(),
                                ),
                                Err(KubeError::Api(err)) if err.code == 404 => Some(0),
                                Err(err) => {
                                    eprintln!(
                                        "Failed to fetch endpoints for service {}: {err}",
                                        state.service_name
                                    );
                                    None
                                }
                            };
                            let replicas_display = match replicas_alive {
                                Some(count) => count.to_string(),
                                None => "Unavailable".to_string(),
                            };
                            let response = format!(
                                r#"<!DOCTYPE html>
<html lang="en">
    <head>
        <meta charset="utf-8" />
        <title>K8s Service Uptime</title>
    </head>
    <body style="font-family: sans-serif; font-size: 32px; margin: 2rem;">
        <div>Hello, Service <strong>{}</strong> has been up for {}</div>
        <div style="margin-top: 0.5rem;">Replicas alive: <strong>{}</strong></div>
        <div style="margin-top: 1rem; font-size: 18px;">
            Created at {} in namespace <code>{}</code>
        </div>
    </body>
</html>"#,
                                state.service_name,
                                format_duration(uptime_std),
                                replicas_display,
                                creation_time.to_rfc3339(),
                                state.namespace
                            );
                            Html(response)
                        } else {
                            Html(render_error(format!(
                                "Creation timestamp {} is in the future.",
                                creation_time.to_rfc3339()
                            )))
                        }
                    }
                    None => Html(render_error(format!(
                        "Service {} is missing a creationTimestamp.",
                        state.service_name
                    ))),
                },
                Err(err) => Html(render_error(format!(
                    "Unable to fetch Service {}: {}",
                    state.service_name, err
                ))),
            }
        }
        None => {
            let base_message =
                "Kubernetes client is not available in this environment.".to_string();
            let details = state
                .client_error
                .clone()
                .map(|msg| format!(" Details: {}", msg))
                .unwrap_or_default();
            Html(render_error(format!("{}{}", base_message, details)))
        }
    }
}

fn render_error(message: String) -> String {
    format!(
        r#"<!DOCTYPE html>
<html lang="en">
    <head>
        <meta charset="utf-8" />
        <title>Service Uptime Error</title>
    </head>
    <body style="font-family: sans-serif; font-size: 24px; margin: 2rem; color: #b91c1c;">
        <div>{}</div>
    </body>
</html>"#,
        message
    )
}

fn detect_namespace() -> String {
    if let Ok(ns) = std::env::var("POD_NAMESPACE") {
        return ns;
    }

    fs::read_to_string("/var/run/secrets/kubernetes.io/serviceaccount/namespace")
        .map(|ns| ns.trim().to_string())
        .unwrap_or_else(|_| "default".to_string())
}

#[tokio::main]
async fn main() {
    let service_name = std::env::var("SERVICE_NAME").unwrap_or_else(|_| "rust-hello".to_string());
    let namespace = detect_namespace();

    let (client, client_error) = match Client::try_default().await {
        Ok(client) => (Some(client), None),
        Err(err) => {
            eprintln!("Failed to create Kubernetes client: {err}");
            (None, Some(err.to_string()))
        }
    };

    let app_state = AppState {
        client,
        client_error,
        namespace,
        service_name,
    };

    let app = Router::new()
        .route("/", get(service_uptime))
        .with_state(app_state);

    let listener = tokio::net::TcpListener::bind("0.0.0.0:3000")
        .await
        .expect("failed to bind address");

    println!("Listening on http://{}", listener.local_addr().unwrap());

    axum::serve(listener, app).await.expect("server error");
}
