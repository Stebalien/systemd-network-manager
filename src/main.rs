use anyhow::Result;
use clap::Parser;
use futures::StreamExt;
use zbus::Connection;

#[allow(unused)]
mod nm_state {
    pub const UNKNOWN: u32 = 0;
    pub const ASLEEP: u32 = 10;
    pub const DISCONNECTED: u32 = 20;
    pub const DISCONNECTING: u32 = 30;
    pub const CONNECTING: u32 = 40;
    pub const CONNECTED_LOCAL: u32 = 50;
    pub const CONNECTED_SITE: u32 = 60;
    pub const CONNECTED_GLOBAL: u32 = 70;
}

static ONLINE_TARGET: &str = "online.target";
static OFFLINE_TARGET: &str = "offline.target";
static CAPTIVE_TARGET: &str = "captive-portal.target";

mod network_manager_iface;
mod systemd_iface;

#[derive(Parser)]
struct Args {
    #[arg(short, long)]
    user: bool,
}

#[tokio::main]
pub async fn main() -> Result<()> {
    let args = Args::parse();
    let nm_conn = Connection::system().await?;
    let sd_conn = if args.user {
        Connection::session().await?
    } else {
        nm_conn.clone()
    };

    let systemd = systemd_iface::ManagerProxy::new(&sd_conn).await?;
    let nm = network_manager_iface::NetworkManagerProxy::new(&nm_conn).await?;

    let mut signals = nm.receive_state_changed().await?;
    while let Some(signal) = signals.next().await {
        let state = signal.args()?.state;
        match state {
            nm_state::CONNECTED_GLOBAL => systemd.start_unit(ONLINE_TARGET, "replace").await?,
            nm_state::CONNECTED_SITE => systemd.start_unit(CAPTIVE_TARGET, "replace").await?,
            nm_state::DISCONNECTED => systemd.start_unit(OFFLINE_TARGET, "replace").await?,
            _ => continue,
        };
    }

    Ok(())
}
