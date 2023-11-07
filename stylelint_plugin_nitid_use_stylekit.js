const stylelint = require('stylelint')

const ruleName = 'nitid/use-stylekit'
const messages = stylelint.utils.ruleMessages(ruleName, {
  rejected: (declaration) =>
    `Expected "${declaration}" to be used within a mixin.`,
})

function isInsideMixin(declaration) {
  let { parent } = declaration
  while (parent) {
    if (parent.type === 'atrule' && parent.name === 'mixin') {
      return true
    }
    parent = parent.parent // eslint-disable-line prefer-destructuring
  }
  return false
}

const pluginRule = stylelint.createPlugin(ruleName, (primaryOption) => {
  return (root, result) => {
    if (!primaryOption || primaryOption.length === 0) return

    root.walkDecls((decl) => {
      if (primaryOption.includes(decl.prop) && !isInsideMixin(decl)) {
        stylelint.utils.report({
          ruleName,
          result,
          node: decl,
          message: messages.rejected(decl.prop),
        })
      }
    })
  }
})

module.exports = pluginRule
module.exports.ruleName = ruleName
module.exports.messages = messages
