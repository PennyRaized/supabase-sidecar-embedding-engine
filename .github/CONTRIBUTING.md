# Contributing to Supabase Sidecar Embedding Engine

Thank you for your interest in contributing! This project demonstrates a production-ready approach to building zero-cost embedding systems, and we welcome contributions that enhance this vision.

## 🎯 Project Philosophy

My philosophy for this project is simple: **build production-grade AI infrastructure without the enterprise price tag.** This is for the builders who want to scale smart, not just scale big.

Every contribution should align with:

- **Zero-cost scaling**: Leveraging existing infrastructure efficiently
- **Production readiness**: Battle-tested patterns and proper error handling
- **Simplicity**: Complex problems solved with elegant solutions
- **Autonomy**: Self-healing, self-managing systems

## 🚀 Getting Started

1. **Fork the repository**
2. **Clone your fork**: `git clone https://github.com/yourusername/supabase-sidecar-embedding-engine.git`
3. **Install dependencies**: `npm install`
4. **Set up environment**: Copy `.env.example` to `.env` and add your credentials
5. **Test the setup**: `node test-setup.js`

## 📋 Types of Contributions

### 🐛 Bug Reports
- Use the bug report template
- Include reproduction steps and environment details
- Test with both small and large document sets

### ✨ Feature Requests
- Use the feature request template
- Explain the use case and business value
- Consider how it fits with the zero-cost philosophy

### 🔧 Code Contributions
- Fork the repository and create a feature branch
- Follow the existing code style and patterns
- Add tests for new functionality
- Update documentation as needed

**Please note:** As this is primarily a personal portfolio project, response times for issues and PRs may vary. However, all contributions will be reviewed thoughtfully and are genuinely appreciated.

## 🏗️ Development Guidelines

### Code Style
- Use TypeScript for type safety
- Follow functional programming patterns where possible
- Prefer database-native solutions over external services
- Include comprehensive error handling

### Testing
- Test with realistic data volumes (1K+ documents)
- Verify autonomous processing behavior
- Test error scenarios and recovery

### Documentation
- Update README for user-facing changes
- Add inline comments for complex logic
- Include migration guides for breaking changes

## 📝 Commit Guidelines

We follow the Conventional Commits specification:

- `feat:` New features
- `fix:` Bug fixes
- `docs:` Documentation changes
- `refactor:` Code refactoring
- `test:` Adding or updating tests
- `perf:` Performance improvements

Example: `feat(queue): add priority-based job processing`

## 🔍 Pull Request Process

1. **Create a descriptive branch name**: `feature/priority-queuing` or `fix/timeout-handling`
2. **Write clear commit messages** following the convention above
3. **Update documentation** if your changes affect user behavior
4. **Add tests** for new functionality
5. **Test thoroughly** with realistic workloads
6. **Fill out the PR template** completely

## 🎯 Areas for Contribution

### High Priority
- Performance optimizations for large datasets
- Additional monitoring and observability features
- Support for alternative embedding providers
- Enhanced error handling and recovery

### Medium Priority
- Multi-model embedding support
- Advanced queue management features
- Migration tools from other systems
- Additional deployment examples

### Documentation
- Tutorial videos and guides
- Architecture deep-dives
- Performance tuning guides
- Migration case studies

## ❓ Questions?

- Check existing issues before creating new ones
- Join discussions on existing issues
- Reach out to maintainers for architectural questions

## 📄 License

By contributing, you agree that your contributions will be licensed under the MIT License.

---

*Thank you for exploring this project. I'm excited to see what we can build together.*
