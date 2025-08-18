-- main.lua — Legal moves + Castling + En Passant (no UI for promotion choice yet)
local S = 80 -- square size

-- ======= GAME STATE =======
local board = {}
local state = {                 -- extra rule state
  castle = { wK=true, wQ=true, bK=true, bQ=true }, -- K-side / Q-side
  enpassant = nil,              -- {r=..., c=...} or nil (target square)
}
local turn = "white"
local selected = nil
local legalTargets = {}
local statusText = ""
local gameOver = false

-- start position (top = black, bottom = white)
local startpos = {
  {"r","n","b","q","k","b","n","r"},
  {"p","p","p","p","p","p","p","p"},
  {" "," "," "," "," "," "," "," "},
  {" "," "," "," "," "," "," "," "},
  {" "," "," "," "," "," "," "," "},
  {" "," "," "," "," "," "," "," "},
  {"P","P","P","P","P","P","P","P"},
  {"R","N","B","Q","K","B","N","R"},
}

-- ======= UTILS =======
local function cloneBoard(b)
  local nb = {}
  for r=1,8 do
    nb[r] = {}
    for c=1,8 do nb[r][c] = b[r][c] end
  end
  return nb
end

local function cloneState(s)
  return {
    enpassant = s.enpassant and { r=s.enpassant.r, c=s.enpassant.c } or nil,
    castle = {
      wK = s.castle.wK, wQ = s.castle.wQ,
      bK = s.castle.bK, bQ = s.castle.bQ
    }
  }
end

local function inBounds(r,c) return r>=1 and r<=8 and c>=1 and c<=8 end
local function isWhite(p) return p ~= " " and p:match("%u") ~= nil end
local function isBlack(p) return p ~= " " and p:match("%l") ~= nil end
local function colorOf(p)
  if p==" " then return nil end
  return isWhite(p) and "white" or "black"
end
local function opp(side) return (side=="white") and "black" or "white" end

local function dirForPawn(color) return (color=="white") and -1 or 1 end
local function startRankForPawn(color) return (color=="white") and 7 or 2 end
local function lastRankForPawn(color) return (color=="white") and 1 or 8 end

-- Sliding helper for B/R/Q
local function slideDirections(ch)
  if ch=="B" or ch=="b" then
    return {{-1,-1},{-1,1},{1,-1},{1,1}}
  elseif ch=="R" or ch=="r" then
    return {{-1,0},{1,0},{0,-1},{0,1}}
  elseif ch=="Q" or ch=="q" then
    return {{-1,-1},{-1,1},{1,-1},{1,1},{-1,0},{1,0},{0,-1},{0,1}}
  else
    return {}
  end
end

-- ======= ATTACK / CHECK =======
local function squareAttackedBy(b, r, c, attacker)
  -- pawns (note reversed perspective for detection)
  local d = dirForPawn(attacker)
  for _,dc in ipairs({-1,1}) do
    local rr,cc = r - d, c - dc
    if inBounds(rr,cc) then
      local p = b[rr][cc]
      if attacker=="white" and p=="P" then return true end
      if attacker=="black" and p=="p" then return true end
    end
  end

  -- knights
  local jumps={{-2,-1},{-2,1},{-1,-2},{-1,2},{1,-2},{1,2},{2,-1},{2,1}}
  for _,d2 in ipairs(jumps) do
    local rr,cc = r+d2[1], c+d2[2]
    if inBounds(rr,cc) then
      local p = b[rr][cc]
      if attacker=="white" and p=="N" then return true end
      if attacker=="black" and p=="n" then return true end
    end
  end

  -- king
  for dr=-1,1 do
    for dc=-1,1 do
      if not (dr==0 and dc==0) then
        local rr,cc=r+dr,c+dc
        if inBounds(rr,cc) then
          local p = b[rr][cc]
          if attacker=="white" and p=="K" then return true end
          if attacker=="black" and p=="k" then return true end
        end
      end
    end
  end

  -- sliders: bishops/rooks/queen
  local function ray(drs, dcs, chars)
    local rr,cc = r+drs, c+dcs
    while inBounds(rr,cc) do
      local p = b[rr][cc]
      if p ~= " " then
        if attacker=="white" and isWhite(p) and chars[p] then return true end
        if attacker=="black" and isBlack(p) and chars[p] then return true end
        break
      end
      rr,cc = rr+drs, cc+dcs
    end
    return false
  end
  -- diagonals (B/Q)
  if ray(-1,-1, attacker=="white" and {B=true,Q=true} or {b=true,q=true}) then return true end
  if ray(-1, 1, attacker=="white" and {B=true,Q=true} or {b=true,q=true}) then return true end
  if ray( 1,-1, attacker=="white" and {B=true,Q=true} or {b=true,q=true}) then return true end
  if ray( 1, 1, attacker=="white" and {B=true,Q=true} or {b=true,q=true}) then return true end
  -- orthogonals (R/Q)
  if ray(-1, 0, attacker=="white" and {R=true,Q=true} or {r=true,q=true}) then return true end
  if ray( 1, 0, attacker=="white" and {R=true,Q=true} or {r=true,q=true}) then return true end
  if ray( 0,-1, attacker=="white" and {R=true,Q=true} or {r=true,q=true}) then return true end
  if ray( 0, 1, attacker=="white" and {R=true,Q=true} or {r=true,q=true}) then return true end

  return false
end

local function findKing(b, side)
  local want = (side=="white") and "K" or "k"
  for r=1,8 do
    for c=1,8 do
      if b[r][c] == want then return r,c end
    end
  end
  return nil,nil
end

local function inCheck(b, side)
  local kr, kc = findKing(b, side)
  if not kr then return false end
  return squareAttackedBy(b, kr, kc, opp(side))
end

-- ======= MOVE GEN (PSEUDO, needs state for special rules) =======
-- Returns list of moves { r=toR, c=toC, castle="K"/"Q"|nil, enpassant=true|nil }
local function targetsFor(b, r, c, st)
  local piece = b[r][c]
  if piece==" " then return {} end
  local side = colorOf(piece)
  local t = {}

  local function add(rr,cc, captureOnly, emptyOnly, flags)
    if not inBounds(rr,cc) then return end
    local dest = b[rr][cc]
    if captureOnly then
      if dest~=" " and colorOf(dest) ~= side then
        local m = {r=rr,c=cc}; if flags then for k,v in pairs(flags) do m[k]=v end end
        table.insert(t, m)
      end
    elseif emptyOnly then
      if dest==" " then
        local m = {r=rr,c=cc}; if flags then for k,v in pairs(flags) do m[k]=v end end
        table.insert(t, m)
      end
    else
      if dest==" " or colorOf(dest) ~= side then
        local m = {r=rr,c=cc}; if flags then for k,v in pairs(flags) do m[k]=v end end
        table.insert(t, m)
      end
    end
  end

  local lower = piece:lower()

  if lower == "p" then
    local d = dirForPawn(side)
    -- forward
    if inBounds(r+d,c) and b[r+d][c]==" " then
      add(r+d, c, false, true)
      if r == startRankForPawn(side) and b[r+2*d] and b[r+2*d][c]==" " then
        add(r+2*d, c, false, true) -- two-step
      end
    end
    -- captures
    add(r+d, c-1, true, false)
    add(r+d, c+1, true, false)
    -- en passant
    if st.enpassant then
      for _,dc in ipairs({-1,1}) do
        local er,ec = r+d, c+dc
        if er==st.enpassant.r and ec==st.enpassant.c and b[r][c]~=" " and b[er][ec]==" " then
          -- destination empty but capture is the pawn beside you
          add(er, ec, false, false, { enpassant = true })
        end
      end
    end

  elseif lower == "n" then
    local jumps = {{-2,-1},{-2,1},{-1,-2},{-1,2},{1,-2},{1,2},{2,-1},{2,1}}
    for _,d in ipairs(jumps) do add(r+d[1], c+d[2]) end

  elseif lower == "k" then
    -- normal king steps
    for dr=-1,1 do
      for dc=-1,1 do
        if not (dr==0 and dc==0) then add(r+dr,c+dc) end
      end
    end
    -- castling (check squares not attacked & path empty & rights)
    -- white king on e1 = (8,5), black king on e8 = (1,5)
    if side=="white" and r==8 and c==5 then
      -- King side: e1->g1 (f1,g1 empty), rook h1 present, rights wK
      if st.castle.wK and b[8][6]==" " and b[8][7]==" " and b[8][8]:lower()=="r" then
        if not inCheck(b,"white")
           and not squareAttackedBy(b,8,6,"black")
           and not squareAttackedBy(b,8,7,"black") then
          add(8,7,false,false,{ castle="K" })
        end
      end
      -- Queen side: e1->c1 (d1,c1,b1 empty), rook a1 present, rights wQ
      if st.castle.wQ and b[8][4]==" " and b[8][3]==" " and b[8][2]==" " and b[8][1]:lower()=="r" then
        if not inCheck(b,"white")
           and not squareAttackedBy(b,8,4,"black")
           and not squareAttackedBy(b,8,3,"black") then
          add(8,3,false,false,{ castle="Q" })
        end
      end
    elseif side=="black" and r==1 and c==5 then
      -- King side: e8->g8
      if st.castle.bK and b[1][6]==" " and b[1][7]==" " and b[1][8]:lower()=="r" then
        if not inCheck(b,"black")
           and not squareAttackedBy(b,1,6,"white")
           and not squareAttackedBy(b,1,7,"white") then
          add(1,7,false,false,{ castle="K" })
        end
      end
      -- Queen side: e8->c8
      if st.castle.bQ and b[1][4]==" " and b[1][3]==" " and b[1][2]==" " and b[1][1]:lower()=="r" then
        if not inCheck(b,"black")
           and not squareAttackedBy(b,1,4,"white")
           and not squareAttackedBy(b,1,3,"white") then
          add(1,3,false,false,{ castle="Q" })
        end
      end
    end

  elseif lower=="b" or lower=="r" or lower=="q" then
    for _,d in ipairs(slideDirections(piece)) do
      local rr,cc = r+d[1], c+d[2]
      while inBounds(rr,cc) do
        local dest = b[rr][cc]
        if dest==" " then
          table.insert(t,{r=rr,c=cc})
        else
          if colorOf(dest) ~= side then table.insert(t,{r=rr,c=cc}) end
          break
        end
        rr,cc = rr + d[1], cc + d[2]
      end
    end
  end

  return t
end

-- ======= APPLY MOVE (PURE: returns nb, nstate) =======
-- move fields: r,c, and optional castle="K"/"Q", enpassant=true
local function applyMove(b, fromR,fromC, move, st)
  local nb = cloneBoard(b)
  local ns = cloneState(st)

  local piece = nb[fromR][fromC]
  local side = colorOf(piece)
  local toR, toC = move.r, move.c
  nb[fromR][fromC] = " "

  -- en passant capture: remove pawn from original file
  if move.enpassant then
    -- captured pawn is on the fromR, toC square
    nb[fromR][toC] = " "
  end

  -- castling: also move rook
  if move.castle == "K" then
    if side=="white" then
      -- King e1->g1, rook h1->f1  (coords: (8,5)->(8,7); (8,8)->(8,6))
      nb[8][6] = nb[8][8]; nb[8][8] = " "
    else
      -- King e8->g8; rook h8->f8  (1,5)->(1,7); (1,8)->(1,6)
      nb[1][6] = nb[1][8]; nb[1][8] = " "
    end
  elseif move.castle == "Q" then
    if side=="white" then
      -- King e1->c1; rook a1->d1  (8,5)->(8,3); (8,1)->(8,4)
      nb[8][4] = nb[8][1]; nb[8][1] = " "
    else
      -- King e8->c8; rook a8->d8  (1,5)->(1,3); (1,1)->(1,4)
      nb[1][4] = nb[1][1]; nb[1][1] = " "
    end
  end

  -- place moving piece (handle promotion)
  if piece:lower()=="p" and toR == lastRankForPawn(side) then
    nb[toR][toC] = isWhite(piece) and "Q" or "q"
  else
    nb[toR][toC] = piece
  end

  -- ===== Update castling rights =====
  local function disableRights(forSide, which) -- which: "K","Q","both"
    if forSide=="white" then
      if which=="K" or which=="both" then ns.castle.wK=false end
      if which=="Q" or which=="both" then ns.castle.wQ=false end
    else
      if which=="K" or which=="both" then ns.castle.bK=false end
      if which=="Q" or which=="both" then ns.castle.bQ=false end
    end
  end

  -- if king moves (or castles) → both rights gone
  if piece=="K" then disableRights("white","both") end
  if piece=="k" then disableRights("black","both") end

  -- if rook moves from original square → disable corresponding side
  if piece=="R" then
    if fromR==8 and fromC==8 then disableRights("white","K") end -- h1
    if fromR==8 and fromC==1 then disableRights("white","Q") end -- a1
  elseif piece=="r" then
    if fromR==1 and fromC==8 then disableRights("black","K") end -- h8
    if fromR==1 and fromC==1 then disableRights("black","Q") end -- a8
  end

  -- if a rook is captured on its original square → disable that right
  -- (check the destination square BEFORE we replaced; but we already placed piece.
  -- So look at 'b' (old board) at destination to see what was captured.)
  local captured = b[toR][toC]
  if captured=="R" then
    if toR==8 and toC==8 then disableRights("white","K") end
    if toR==8 and toC==1 then disableRights("white","Q") end
  elseif captured=="r" then
    if toR==1 and toC==8 then disableRights("black","K") end
    if toR==1 and toC==1 then disableRights("black","Q") end
  end

  -- if castled → obviously rights are gone
  if move.castle then
    disableRights(side,"both")
  end

  -- ===== Update en passant target =====
  ns.enpassant = nil
  if piece:lower()=="p" then
    local d = dirForPawn(side)
    if math.abs(toR - fromR) == 2 then
      -- target is the square jumped over
      ns.enpassant = { r = fromR + d, c = fromC }
    end
  end

  return nb, ns
end

-- ======= LEGAL FILTER =======
local function legalTargetsFor(b, r, c, st)
  local piece = b[r][c]
  if piece==" " then return {} end
  local side = colorOf(piece)
  if side ~= turn then return {} end

  local out = {}
  local pseudo = targetsFor(b, r, c, st)
  for _,m in ipairs(pseudo) do
    local nb, ns = applyMove(b, r, c, m, st)
    if not inCheck(nb, side) then
      table.insert(out, m)
    end
  end
  return out
end

local function anyLegalMove(b, side, st)
  for r=1,8 do
    for c=1,8 do
      local p = b[r][c]
      if p ~= " " and colorOf(p)==side then
        local pseudo = targetsFor(b, r, c, st)
        for _,m in ipairs(pseudo) do
          local nb, ns = applyMove(b, r, c, m, st)
          if not inCheck(nb, side) then return true end
        end
      end
    end
  end
  return false
end

local function updateStatus()
  if gameOver then return end
  local side = turn
  local check = inCheck(board, side)
  local hasMove = anyLegalMove(board, side, state)
  if not hasMove and check then
    statusText = (side=="white" and "White" or "Black") .. " is checkmated!"
    gameOver = true
  elseif not hasMove then
    statusText = "Stalemate!"
    gameOver = true
  elseif check then
    statusText = (side=="white" and "White" or "Black") .. " is in check."
  else
    statusText = ""
  end
end

-- ======= UI helpers & LOVE callbacks =======
local function coordsToSquare(x,y)
  local c = math.floor(x / S) + 1
  local r = math.floor(y / S) + 1
  if inBounds(r,c) then return r,c end
  return nil,nil
end

local function findInTargets(list, r,c)
  for _,m in ipairs(list) do if m.r==r and m.c==c then return m end end
  return nil
end

function love.load()
  for r=1,8 do
    board[r] = {}
    for c=1,8 do board[r][c] = startpos[r][c] end
  end
  state = { castle = { wK=true,wQ=true,bK=true,bQ=true }, enpassant=nil }
  turn, selected, legalTargets, gameOver, statusText = "white", nil, {}, false, ""
  love.window.setMode(S*8, S*8)
  love.window.setTitle("Lua + LÖVE Chess — castling + en passant")
  updateStatus()
end

function love.keypressed(key)
  if key=="r" then love.load() end
end

function love.draw()
  -- board
  for r=1,8 do
    for c=1,8 do
      if (r+c)%2==0 then love.graphics.setColor(0.9,0.9,0.9) else love.graphics.setColor(0.25,0.45,0.25) end
      love.graphics.rectangle("fill", (c-1)*S, (r-1)*S, S, S)
    end
  end

  -- selection
  if selected then
    love.graphics.setColor(1,1,0,0.35)
    love.graphics.rectangle("fill", (selected.c-1)*S, (selected.r-1)*S, S, S)
  end

  -- legal target dots
  for _,m in ipairs(legalTargets) do
    love.graphics.setColor(0,0,0,0.35)
    love.graphics.circle("fill", (m.c-0.5)*S, (m.r-0.5)*S, S*0.15)
  end

  -- pieces
  for r=1,8 do
    for c=1,8 do
      local piece = board[r][c]
      if piece ~= " " then
        love.graphics.setColor(0,0,0)
        love.graphics.printf(piece, (c-1)*S, (r-1)*S + S/3, S, "center")
      end
    end
  end

  -- HUD
  love.graphics.setColor(0,0,0)
  love.graphics.print("Turn: "..turn, 8, 8)
  if state.enpassant then
    love.graphics.print(("EP: %d,%d"):format(state.enpassant.r, state.enpassant.c), 8, 28)
  end
  if statusText ~= "" then
    love.graphics.print(statusText, 8, 48)
  end
  if gameOver then
    love.graphics.print("Game Over — press R to restart", 8, 68)
  end
end

function love.mousepressed(x,y,button)
  if button ~= 1 or gameOver then return end
  local r,c = coordsToSquare(x,y)
  if not r then return end

  if not selected then
    local p = board[r][c]
    if p ~= " " and colorOf(p)==turn then
      selected = {r=r,c=c}
      legalTargets = legalTargetsFor(board, r, c, state)
    end
  else
    local move = findInTargets(legalTargets, r, c)
    if move then
      board, state = applyMove(board, selected.r, selected.c, move, state)
      turn = opp(turn)
      selected, legalTargets = nil, {}
      updateStatus()
    else
      local p = board[r][c]
      if p ~= " " and colorOf(p)==turn then
        selected = {r=r,c=c}
        legalTargets = legalTargetsFor(board, r, c, state)
        return
      end
      selected, legalTargets = nil, {}
    end
  end
end
