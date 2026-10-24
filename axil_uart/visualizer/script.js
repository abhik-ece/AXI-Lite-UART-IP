const descriptions = {
  "AXI-Lite Host": "External bus master that initiates register reads and writes using AXI-Lite channels.",
  "Register Interface": "Maps bus transactions to UART configuration, transmit data, receive data, and status registers. Confirm register details in axil_uart_regs.v.",
  "TX FIFO": "Buffers bytes waiting to be transmitted. The exact depth and handshake behavior should be confirmed in sync_fifo.v and the top-level RTL.",
  "UART TX": "Converts a parallel transmit byte into UART serial framing on TXD.",
  "TXD Serial Output": "Serial transmit pin. UART idle is commonly high; verify the implementation and waveform for this design.",
  "RX FIFO": "Buffers received data for software or a bus master to read.",
  "UART RX": "Samples the RXD serial input and reconstructs received data and status information.",
  "RXD Serial Input": "Serial receive pin driven by an external UART peer or the testbench.",
  "Status and Control": "Conceptual view of configuration and status registers, including flags visible in the provided GTKWave captures."
};

document.querySelectorAll(".node").forEach(node => {
  const activate = () => {
    document.querySelectorAll(".node").forEach(n => n.classList.remove("selected"));
    node.classList.add("selected");
    const name = node.dataset.name;
    document.querySelector("#moduleInfo").innerHTML = `<strong>${name}</strong><span>${descriptions[name] || "Module in the UART data path."}</span>`;
  };
  node.addEventListener("click", activate);
  node.addEventListener("keydown", e => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); activate(); } });
});

const txBtn = document.querySelector("#txBtn");
const rxBtn = document.querySelector("#rxBtn");
const stopBtn = document.querySelector("#stopBtn");
const txPacket = document.querySelector("#txPacket");
const rxPacket = document.querySelector("#rxPacket");
const flowSteps = document.querySelector("#flowSteps");
const flowTitle = document.querySelector("#flowTitle");
const flowBadge = document.querySelector("#flowBadge");
const flowCaption = document.querySelector("#flowCaption");
let mode = "tx", timer = null, step = 0;
const txPositions = [[200,235],[310,235],[440,235],[570,130],[765,130],[850,130],[935,130]];
const rxPositions = [[935,350],[850,365],[765,365],[570,365],[440,365],[310,365],[310,235]];
const txLabels = ["AXI-Lite write","Register interface","TX FIFO","UART TX serializer","TXD pin"];
const rxLabels = ["RXD pin","UART RX sampler","RX FIFO","Register / status path","AXI-Lite read"];
function renderSteps() {
  const labels = mode === "tx" ? txLabels : rxLabels;
  flowSteps.innerHTML = labels.map((label,i)=>`<div class="flow-step ${i===step%labels.length ? (mode==="tx"?"current":"rx-current"):""}"><b>${i+1}</b><span>${label}</span></div>`).join("");
  flowTitle.textContent = mode === "tx" ? "Transmit path" : "Receive path";
  flowBadge.textContent = mode.toUpperCase();
  flowBadge.className = "flow-badge " + mode;
  flowCaption.textContent = mode === "tx"
    ? "Conceptual TX flow: AXI-Lite write → register interface → TX buffering → UART serialization → TXD."
    : "Conceptual RX flow: RXD → UART sampling and decoding → RX buffering → register/status path → AXI-Lite read.";
}
function tick() {
  const points = mode === "tx" ? txPositions : rxPositions;
  const p = points[step % points.length];
  const packet = mode === "tx" ? txPacket : rxPacket;
  packet.setAttribute("cx", p[0]); packet.setAttribute("cy", p[1]);
  step++;
  renderSteps();
}
function start(nextMode) {
  mode = nextMode; step = 0;
  clearInterval(timer);
  txPacket.style.display = mode === "tx" ? "block" : "none";
  rxPacket.style.display = mode === "rx" ? "block" : "none";
  txBtn.classList.toggle("active", mode === "tx");
  rxBtn.classList.toggle("active", mode === "rx");
  tick();
  timer = setInterval(tick, 850);
}
txBtn.addEventListener("click", () => start("tx"));
rxBtn.addEventListener("click", () => start("rx"));
stopBtn.addEventListener("click", () => {
  clearInterval(timer); timer = null;
  stopBtn.textContent = "Paused";
  setTimeout(() => stopBtn.textContent = "Pause", 900);
});
start("tx");
