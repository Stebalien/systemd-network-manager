use std::time::Duration;

use anyhow::Result;
use clap::Parser;
use tokio::time;
use tokio_stream::StreamExt;
use zbus::Connection;

static ONLINE_TARGET: &str = "online.target";
static OFFLINE_TARGET: &str = "offline.target";
static CAPTIVE_TARGET: &str = "captive-portal.target";

mod networkd_iface;
mod systemd_iface;

const PING_SLEEP: Duration = Duration::from_secs(3);

const PING_URL: &str = "https://1.1.1.1";

#[derive(Parser)]
struct Args {
    #[arg(short, long)]
    user: bool,
}

async fn handle_state_change(
    systemd: &systemd_iface::ManagerProxy<'_>,
    current_state: &str,
) -> Result<()> {
    if current_state != "routable" {
        systemd.start_unit(OFFLINE_TARGET, "replace").await?;
        return Ok(());
    }

    let mut count = 0;
    while !ping().await {
        if count == 1 {
            systemd.start_unit(CAPTIVE_TARGET, "replace").await?;
        }
        time::sleep(PING_SLEEP).await;
        count += 1;
    }
    systemd.start_unit(ONLINE_TARGET, "replace").await?;
    Ok(())
}

pub async fn ping() -> bool {
    reqwest::Client::builder()
        .build()
        .unwrap()
        .head(PING_URL)
        .send()
        .await
        .is_ok()
}

#[tokio::main(flavor = "current_thread")]
pub async fn main() -> Result<()> {
    let args = Args::parse();
    let nm_conn = Connection::system().await?;
    let sd_conn = if args.user {
        Connection::session().await?
    } else {
        nm_conn.clone()
    };

    let systemd = systemd_iface::ManagerProxy::new(&sd_conn).await?;
    let nm = networkd_iface::ManagerProxy::new(&nm_conn).await?;

    // States, filtered to only the ones we care about.
    let mut states = nm.receive_operational_state_changed().await;
    let mut current_state = nm.operational_state().await?;
    loop {
        let active_task = handle_state_change(&systemd, &current_state);
        let state = tokio::select! {
            state = states.next() => state,
            result = active_task => {
                result?;
                states.next().await
            }
        };
        match state {
            Some(state) => {
                current_state = state.get().await?;
            }
            None => return Ok(()),
        }
    }
}
