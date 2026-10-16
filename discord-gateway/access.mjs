// Pure, side-effect-free authorization helpers for the local Gateway worker.
export function isOwnerInteraction(interaction, userId, channelId) {
  if (!interaction || !userId || !channelId) return false;
  const caller = String(interaction.member?.user?.id || interaction.user?.id || "");
  return caller === String(userId)
    && String(interaction.channel_id || "") === String(channelId);
}

export function guildFromConfiguredChannel(channel, expectedChannelId) {
  if (!channel || String(channel.id || "") !== String(expectedChannelId)) return "";
  const guildId = String(channel.guild_id || "");
  return /^\d{15,22}$/.test(guildId) ? guildId : "";
}
