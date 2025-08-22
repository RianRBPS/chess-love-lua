# ♟️ Chess in Lua + LÖVE — Learning Project

## 1. Why Lua?
- Lua is a lightweight, embeddable programming language created in Brazil (PUC-Rio).
- Designed to be simple, fast, and easy to integrate into larger systems.
- Powers many games and engines — from **Roblox** to **World of Warcraft**.

## 2. Why LÖVE (Love2D)?
- LÖVE is a 2D game framework that uses Lua as its scripting language.
- Handles graphics, input, and sound so you can focus on game logic.
- Popular among indie developers: for example, **Balatro** — the hit roguelike deck-building poker game — was built entirely with Lua and LÖVE, showing how powerful yet accessible the framework can be.

## 3. Inspiration: Balatro
- **Balatro (2024)** reimagines poker as a chaotic roguelike deckbuilder.
- It shows how a rigid classic game can be transformed into something creative and modern.
- This project starts with **classic chess** as a learning base, but with Balatro in mind — the same approach could later be used to add twists, randomness, and roguelike flavor to chess.

## 4. Project Overview
### Features Implemented
- ✅ 8×8 chessboard  
- ✅ Piece logic (all standard moves)  
- ✅ Special rules (promotion, castling, en passant)  
- ✅ Promotion UI with choice  
- ✅ Pieces displayed as PNGs  
- ✅ Simple AI opponent  

## 5. AI Overview
The AI uses basic chess engine ideas:
- **Move Generation** — lists all legal moves.  
- **Evaluation** — simple material values (Pawn = 100, Knight/Bishop = 300, Rook = 500, Queen = 900).  
- **Search** — minimax with alpha-beta pruning.  
- **Hashing** — Zobrist-like hashing for efficient board state lookup.  

⚠️ *Note: The AI sometimes blunders (e.g. sacrificing the queen) because the evaluation function is very basic.*

## 6. Current Status
### Working
- Full chess rules implemented.  
- AI can play complete games.  
- Promotion UI and sprites working.  

### Limitations
- Weak AI (no sense of strategy or king safety).  
- All code currently in a single `main.lua`.  
- Missing advanced rules (stalemate, 50-move rule, repetition).  

## 7. Next Steps
- Improve AI evaluation with positional factors.  
- Modularize code into separate files.  
- Add animations, sounds, clocks, move history.  
- Experiment with Balatro-style twists: random modifiers, power-ups, variant boards.  

## 8. Takeaways
- Learned Lua syntax and structure.  
- Understood LÖVE’s game loop.  
- Built a complete chess game from scratch.  
- Implemented AI fundamentals (search + evaluation).  
- Connected to modern design inspiration (*Balatro*) to imagine future directions.  
