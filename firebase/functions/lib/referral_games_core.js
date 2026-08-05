"use strict";

const crypto = require("crypto");

function getTrimmedString(value) {
  return typeof value === "string" ? value.trim() : "";
}

// Tire un ticket au hasard (uniforme) parmi une liste de tickets, un doc par
// parrainage valide. Un inviter_uid qui apparait plusieurs fois a donc
// mecaniquement une probabilite proportionnelle a son nombre de tickets --
// pas d'algorithme de ponderation separe a maintenir.
function pickWinningTicket(tickets, randomInt = crypto.randomInt) {
  if (!Array.isArray(tickets) || tickets.length === 0) {
    return null;
  }

  const randomIndex = randomInt(0, tickets.length);
  const winningTicket = tickets[randomIndex];
  const winnerUid = getTrimmedString(winningTicket && winningTicket.inviter_uid);
  const winnerTicketCount = tickets.filter(
    (ticket) => getTrimmedString(ticket && ticket.inviter_uid) === winnerUid
  ).length;

  return {
    winningTicket,
    winnerUid,
    winnerTicketCount,
    totalTicketCount: tickets.length,
  };
}

module.exports = { pickWinningTicket };
