import fs from "node:fs/promises";
import path from "node:path";
import { isOwnerInteraction, guildFromConfiguredChannel } from "./access.mjs";
import {
  COMMANDS,
  buildDeferredResponse,
  buildIdentifyPayload,
  buildInteractionJob,
  interactionCommand
} from "./protocol.mjs";

const API = "https://discord.com/api/v10";
const token = (process.env.ULTIMATE_MACRO_DISCORD_TOKEN || "").trim();
const privateChannelId = (process.env.ULTIMATE_MACRO_DISCORD_CHANNEL_ID || "").trim();
const privateUserId = (process.env.ULTIMATE_MACRO_DISCORD_USER_ID || "").trim();
const rootDir = process.env.ULTIMATE_MACRO_DISCORD_GATEWAY_DIR;
const commandDir = rootDir ? path.join(rootDir, "commands") : "";
const statusPath = rootDir ? path.join(rootDir, "status.json") : "";
const nodeMajorVersion = Number.parseInt(process.versions.node.split(".")[0], 10);

let socket = null;
let heartbeatTimer = null;
let reconnectTimer = null;
let reconnectDelay = 1000;
let sequence = null;
let sessionId = "";
let resumeGatewayUrl = "";
let applicationId = "";
let privateGuildId = "";
let shuttingDown = false;
const inFlight = new Set();
const registeredGuilds = new Set();

let status = {
  state: "starting",
  message: "Starting the slash-command gateway.",
  guild_count: 0,
  updated_at: new Date().toISOString()
};

async function writeStatus(state, message = "", details = {}) {
  status = {
    ...status,
    state,
    message,
    ...details,
    updated_at: new Date().toISOString()
  };
  if (!statusPath) return;
  try {
    await fs.mkdir(rootDir, { recursive: true });
    const tempPath = `${statusPath}.${process.pid}.tmp`;
    await fs.writeFile(tempPath, JSON.stringify(status), "utf8");
    await fs.rm(statusPath, { force: true });
    await fs.rename(tempPath, statusPath);
  } catch (error) {
    console.error(`[discord-gateway] status write failed: ${error.message}`);
  }
}

async function apiRequest(endpoint, init = {}, authorize = false) {
  const headers = {
    "Content-Type": "application/json",
    ...(init.headers || {})
  };
  if (authorize) headers.Authorization = `Bot ${token}`;

  const response = await fetch(`${API}${endpoint}`, {
    ...init,
    headers
  });
  const text = await response.text();
  let body = null;
  try {
    body = text ? JSON.parse(text) : null;
  } catch {
    body = text;
  }
  if (!response.ok) {
    const detail = body && typeof body === "object" && body.message ? `: ${body.message}` : "";
    const error = new Error(`Discord HTTP ${response.status}${detail}`);
    error.status = response.status;
    const retryAfter = Number(response.headers.get("retry-after"));
    error.retryAfterMs = Number.isFinite(retryAfter) && retryAfter > 0
      ? Math.ceil(retryAfter * 1000)
      : 0;
    throw error;
  }
  return body;
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function commandUrl(targetGuildId) {
  return `/applications/${applicationId}/guilds/${targetGuildId}/commands`;
}

async function registerGuildCommands(targetGuildId) {
  // POST upserts each of OUR commands by name. Unlike bulk PUT, this does not
  // delete unrelated slash commands from the owner's personal Discord bot.
  for (const command of COMMANDS) {
    let lastError = null;
    for (let attempt = 0; attempt < 4; attempt += 1) {
      try {
        await apiRequest(commandUrl(targetGuildId), {
          method: "POST",
          body: JSON.stringify(command)
        }, true);
        lastError = null;
        break;
      } catch (error) {
        lastError = error;
        const retryable = error?.status === 429 || (error?.status >= 500 && error?.status <= 599);
        if (!retryable || attempt === 3) throw error;
        const delay = Math.min(15000, error?.retryAfterMs || (1000 * (attempt + 1)));
        await sleep(delay);
      }
    }
    if (lastError) throw lastError;
  }
}

async function registerCommands(targetGuildIds) {
  const guildIds = [...new Set(targetGuildIds.map((value) => String(value || "").trim()).filter(Boolean))];
  if (!applicationId || guildIds.length === 0) return 0;

  const results = await Promise.allSettled(guildIds.map((targetGuildId) => registerGuildCommands(targetGuildId)));
  const failures = results.filter((result) => result.status === "rejected");
  for (let index = 0; index < results.length; index += 1) {
    if (results[index].status === "fulfilled") registeredGuilds.add(guildIds[index]);
  }
  if (failures.length) {
    const reason = failures[0].reason?.message || "unknown Discord error";
    throw new Error(`Discord rejected command registration in ${failures.length} server${failures.length === 1 ? "" : "s"}: ${reason}`);
  }
  return guildIds.length;
}

function send(packet) {
  if (socket && socket.readyState === WebSocket.OPEN) {
    socket.send(JSON.stringify(packet));
  }
}

function stopHeartbeat() {
  if (heartbeatTimer) clearTimeout(heartbeatTimer);
  heartbeatTimer = null;
}

function startHeartbeat(interval) {
  stopHeartbeat();
  const schedule = (delay) => {
    heartbeatTimer = setTimeout(() => {
      send({ op: 1, d: sequence });
      schedule(interval);
    }, delay);
  };
  schedule(Math.floor(Math.random() * interval));
}

function gatewayUrl() {
  const base = resumeGatewayUrl || "wss://gateway.discord.gg/";
  return `${base}${base.includes("?") ? "&" : "?"}v=10&encoding=json`;
}

function identifyOrResume() {
  if (sessionId && resumeGatewayUrl && sequence !== null) {
    send({
      op: 6,
      d: { token, session_id: sessionId, seq: sequence }
    });
    return;
  }

  send(buildIdentifyPayload(token));
}

async function acknowledgeInteraction(interaction) {
  await apiRequest(`/interactions/${interaction.id}/${interaction.token}/callback`, {
    method: "POST",
    body: JSON.stringify(buildDeferredResponse())
  });
}

async function enqueueInteraction(interaction, name, argument = "") {
  if (!commandDir) throw new Error("The gateway command directory is not configured.");
  const job = buildInteractionJob(interaction, applicationId, name, argument);
  await fs.mkdir(commandDir, { recursive: true });
  const finalPath = path.join(commandDir, `${job.id}.json`);
  const tempPath = `${finalPath}.${process.pid}.tmp`;
  await fs.writeFile(tempPath, JSON.stringify(job), "utf8");
  await fs.rm(finalPath, { force: true });
  await fs.rename(tempPath, finalPath);
}

async function handleInteraction(interaction) {
  if (inFlight.has(String(interaction.id))) return;
  // Ignore unauthorized commands before they reach the local command queue.
  // Reply privately so other members cannot learn the owner's configuration.
  if (!isOwnerInteraction(interaction, privateUserId, privateChannelId)) {
    try {
      await apiRequest(`/interactions/${interaction.id}/${interaction.token}/callback`, {
        method: "POST",
        body: JSON.stringify({
          type: 4,
          data: { content: "This Ultimate Macro remote is private.", flags: 64,
            allowed_mentions: { parse: [] } }
        })
      });
    } catch { /* Interaction may have already expired; do not retry. */ }
    return;
  }
  inFlight.add(String(interaction.id));
  try {
    const command = interactionCommand(interaction);
    if (!command?.name) return;

    await acknowledgeInteraction(interaction);
    await enqueueInteraction(interaction, command.name, command.argument);
  } catch (error) {
    await writeStatus("error", `Interaction handling failed: ${error.message}`);
  } finally {
    inFlight.delete(String(interaction.id));
  }
}

async function handlePacket(packet) {
  if (packet.s !== null && packet.s !== undefined) sequence = packet.s;

  if (packet.op === 10) {
    startHeartbeat(packet.d.heartbeat_interval);
    identifyOrResume();
    return;
  }
  if (packet.op === 1) {
    send({ op: 1, d: sequence });
    return;
  }
  if (packet.op === 7) {
    socket?.close();
    return;
  }
  if (packet.op === 9) {
    sessionId = "";
    resumeGatewayUrl = "";
    sequence = null;
    if (packet.d === false) socket?.close();
    return;
  }
  if (packet.op !== 0) return;

  if (packet.t === "READY") {
    sessionId = String(packet.d.session_id || "");
    resumeGatewayUrl = String(packet.d.resume_gateway_url || "");
    applicationId = String(packet.d.application?.id || "");
    try {
      // Only register slash commands in the server containing the configured
      // private channel, never in every server that happens to share this bot.
      const configuredChannel = await apiRequest(`/channels/${privateChannelId}`, {}, true);
      privateGuildId = guildFromConfiguredChannel(configuredChannel, privateChannelId);
      if (!privateGuildId) {
        throw new Error("Configured personal bot channel is not a guild text channel the bot can access.");
      }
      await registerCommands([privateGuildId]);
      reconnectDelay = 1000;
      await writeStatus("ready", "Slash commands are connected in the configured server.", {
        guild_count: 1
      });
    } catch (error) {
      await writeStatus("error", `Slash commands could not be registered: ${error.message}`, {
        guild_count: registeredGuilds.size
      });
    }
    return;
  }
  if (packet.t === "GUILD_CREATE" && packet.d?.id && String(packet.d.id) === privateGuildId) {
    try {
      await registerCommands([packet.d.id]);
      await writeStatus("ready", "Slash commands are connected.", {
        guild_count: registeredGuilds.size
      });
    } catch (error) {
      await writeStatus("error", `Slash commands could not be registered: ${error.message}`, {
        guild_count: registeredGuilds.size
      });
    }
    return;
  }
  if (packet.t === "INTERACTION_CREATE") {
    await handleInteraction(packet.d);
  }
}

function scheduleReconnect() {
  if (shuttingDown || reconnectTimer) return;
  const delay = reconnectDelay;
  reconnectDelay = Math.min(30000, reconnectDelay * 2);
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null;
    connect();
  }, delay);
}

async function connect() {
  if (shuttingDown) return;
  await writeStatus("starting", "Connecting to Discord.");
  socket = new WebSocket(gatewayUrl());
  socket.addEventListener("open", () => {
    reconnectDelay = 1000;
  });
  socket.addEventListener("message", (event) => {
    try {
      void handlePacket(JSON.parse(String(event.data))).catch((error) => {
        void writeStatus("error", `Gateway payload failed: ${error.message}`);
      });
    } catch (error) {
      void writeStatus("error", `Gateway payload failed: ${error.message}`);
    }
  });
  socket.addEventListener("error", () => {
    void writeStatus("error", "The Discord Gateway connection failed.");
  });
  socket.addEventListener("close", () => {
    stopHeartbeat();
    socket = null;
    if (!shuttingDown) {
      void writeStatus("starting", "Discord disconnected; reconnecting.");
      scheduleReconnect();
    }
  });
}

async function shutdown() {
  if (shuttingDown) return;
  shuttingDown = true;
  if (reconnectTimer) clearTimeout(reconnectTimer);
  reconnectTimer = null;
  stopHeartbeat();
  try {
    socket?.close(1000, "shutdown");
  } catch {
    // The process is exiting; there is nothing useful to recover here.
  }
  await writeStatus("stopped", "The slash-command gateway is stopped.");
  process.exit(0);
}

process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);

if (!token || !rootDir || !/^\d{15,22}$/.test(privateChannelId)
    || !/^\d{15,22}$/.test(privateUserId)) {
  await writeStatus("error", "Bot token, permitted user or channel configuration is missing.");
  process.exit(1);
}

if (nodeMajorVersion < 22 || typeof WebSocket !== "function") {
  await writeStatus("error", "Node.js 22 or newer with WebSocket support is required.");
  process.exit(1);
}

await fs.mkdir(commandDir, { recursive: true });
await writeStatus("starting", "Starting the slash-command gateway.");
await connect();
