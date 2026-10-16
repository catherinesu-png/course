/// The starting point for new games, same as the web builder's template.
enum GameTemplate {
    static let code = """
    <!doctype html>
    <html>
    <head><meta name="viewport" content="width=device-width, initial-scale=1"></head>
    <body style="font-family: sans-serif; padding: 16px">
    <h2>Race to 10</h2>
    <p id="status">Waiting for the platform…</p>
    <p>Total: <b id="total">0</b></p>
    <button id="add1">+1</button> <button id="add2">+2</button>
    <script>
    let latest = null; // the last state_changed message
    function add(n) {
      const seat = latest.acting_for_player_index;
      const total = (latest.state ? latest.state.total : 0) + n;
      const won = total >= 10;
      parent.postMessage({
        type: "make_move",
        new_state: { total, winner: won ? seat : null },
        next_turn_player_indices: won ? null : [(seat + 1) % latest.players.length],
      }, "*");
    }
    addEventListener("message", (event) => {
      if (event.source !== parent || !event.data || event.data.type !== "state_changed") return;
      latest = event.data;
      const state = latest.state || { total: 0, winner: null };
      const acting = latest.status === "ongoing" ? latest.acting_for_player_index : null;
      document.getElementById("total").textContent = state.total;
      document.getElementById("status").textContent = state.winner !== null
        ? latest.players[state.winner].name + " wins!"
        : acting === null ? "Waiting for another player…" : latest.players[acting].name + "'s turn";
      for (const id of ["add1", "add2"]) document.getElementById(id).disabled = acting === null;
      // Computers' moves are computed by the game, for whichever client acts for them.
      if (acting !== null && latest.players[acting].kind === "computer") {
        setTimeout(() => add(1 + Math.floor(Math.random() * 2)), 500);
      }
    });
    document.getElementById("add1").onclick = () => add(1);
    document.getElementById("add2").onclick = () => add(2);
    </script>
    </body>
    </html>

    """
}
