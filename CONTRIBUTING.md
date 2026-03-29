# Contributing

Thanks for your interest in contributing to OpenClaw Business Analyst Bot!

## Getting Started

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-change`)
3. Make your changes
4. Run the bot locally to verify everything works
5. Commit your changes (`git commit -m 'Add my change'`)
6. Push to your fork (`git push origin feature/my-change`)
7. Open a Pull Request

## Security

- **Never commit `.env` files** with real credentials. The `.gitignore` already excludes `.env`, but always verify with `git status` before pushing.
- **Never commit API keys, tokens, or passwords** in code or config files.
- Use `.env.example` as a template — it contains only placeholder values.
- If you discover a security vulnerability, please report it privately via GitHub's security advisory feature rather than opening a public issue.

## Guidelines

- Keep changes focused — one feature or fix per PR.
- Update the README if your change affects setup or usage.
- All generated database data should remain synthetic — do not add real customer or business data.

## Questions?

Open an issue if you have questions or want to discuss a change before starting work.
