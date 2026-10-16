export const COMMANDS = [
  { name: "help", description: "Show the available bot commands." },
  { name: "ping", description: "Check whether the bot is online." },
  { name: "version", description: "Show the macro version." },
  { name: "current", description: "Show the active strategy and runtime." },
  { name: "stats", description: "Show saved wins, losses, and resources." },
  { name: "status", description: "Show the current macro status." },
  { name: "health", description: "Show bot connection status." },
  { name: "screenshot", description: "Capture the Roblox window." },
  { name: "start", description: "Queue the macro to start." },
  { name: "stop", description: "Stop the macro if it is running." },
  { name: "exportlogs", description: "Upload redacted diagnostic logs." },
  { name: "strat", description: "Choose and start a strategy." }
].map((command) => ({ type: 1, ...command }));

export function buildIdentifyPayload(token) {
  return {
    op: 2,
    d: {
      token,
      intents: 1,
      properties: {
        os: "windows",
        browser: "ultimate-macro",
        device: "ultimate-macro"
      }
    }
  };
}

export function buildDeferredResponse() {
  return { type: 5 };
}

export function interactionCommand(interaction) {
  if (interaction?.type === 2) {
    const name = String(interaction.data?.name || "").toLowerCase();
    const option = interaction.data?.options?.find((candidate) => candidate.name === "number");
    return {
      name,
      argument: option && option.value !== undefined ? String(option.value) : ""
    };
  }
  if (interaction?.type === 3 && interaction.data?.custom_id === "bot:health") {
    return { name: "health", argument: "" };
  }
  if (interaction?.type === 3) {
    const match = /^bot:strats:\d+$/.exec(String(interaction.data?.custom_id || ""));
    const value = interaction.data?.values?.[0];
    if (match && value !== undefined) {
      return { name: "strat", argument: String(value) };
    }
  }
  return null;
}

export function buildInteractionJob(interaction, applicationId, name, argument = "") {
  return {
    id: String(interaction.id),
    name,
    argument,
    user_id: interaction.member?.user?.id || interaction.user?.id || "",
    channel_id: String(interaction.channel_id || ""),
    guild_id: String(interaction.guild_id || ""),
    interaction: {
      id: String(interaction.id),
      token: String(interaction.token),
      application_id: String(interaction.application_id || applicationId),
      channel_id: String(interaction.channel_id || ""),
      guild_id: String(interaction.guild_id || "")
    }
  };
}
