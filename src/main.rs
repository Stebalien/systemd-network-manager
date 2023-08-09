use std::time::Duration;

use anyhow::Result;
use clap::Parser;
use tokio::time;
use tokio_stream::StreamExt;
use zbus::zvariant::OwnedObjectPath;
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

const CONNECTIVITY_TIMEOUT: Duration = Duration::from_secs(4);
const OFFLINE_DELAY: Duration = Duration::from_secs(2);

#[derive(Parser)]
struct Args {
    #[arg(short, long)]
    user: bool,
}

#[derive(Debug, Copy, Clone, Default)]
enum ConnectivityState {
    #[default]
    Offline,
    Online,
    CaptivePortal,
}

impl TryFrom<u32> for ConnectivityState {
    type Error = u32;

    fn try_from(value: u32) -> std::result::Result<Self, Self::Error> {
        use ConnectivityState::*;
        match value {
            nm_state::DISCONNECTED => Ok(Offline),
            nm_state::CONNECTED_GLOBAL => Ok(Online),
            nm_state::CONNECTED_SITE => Ok(CaptivePortal),
            e => Err(e),
        }
    }
}

async fn handle_state_change(
    systemd: &systemd_iface::ManagerProxy<'_>,
    state: ConnectivityState,
) -> Result<OwnedObjectPath> {
    Ok(match state {
        ConnectivityState::Online => systemd.start_unit(ONLINE_TARGET, "replace").await?,
        ConnectivityState::Offline => {
            // We wait a few seconds before going offline to avoid network "blips" restarting
            // things.
            time::sleep(OFFLINE_DELAY).await;
            systemd.start_unit(OFFLINE_TARGET, "replace").await?
        }
        ConnectivityState::CaptivePortal => {
            // We wait a few seconds before transitioning to the "captive portal" target to avoid
            // opening a login page unnecessarily. Might be better to just make it less intrusive,
            // but network blips can cause the same issues... so it's better to just have a little
            // delay here.
            time::sleep(CONNECTIVITY_TIMEOUT).await;
            systemd.start_unit(CAPTIVE_TARGET, "replace").await?
        }
    })
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
    let nm = network_manager_iface::NetworkManagerProxy::new(&nm_conn).await?;

    // States, filtered to only the ones we care about.
    let mut states = nm
        .receive_state_changed()
        .await?
        .filter_map(|s| s.args().map(|s| s.state.try_into().ok()).transpose());
    let mut next_state = nm.state().await?.try_into().unwrap_or_default();
    loop {
        let active_task = handle_state_change(&systemd, next_state);
        tokio::select! {
            state = states.next() => match state {
                Some(state) => {
                    next_state = state?;
                },
                None => return Ok(()),
            },
            result = active_task => {
                result?;
            }
        }
    }
}
