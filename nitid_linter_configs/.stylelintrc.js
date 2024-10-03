module.exports = {
  customSyntax: 'postcss-scss',
  extends: ['stylelint-prettier/recommended'],
  plugins: ['@nitid/stylelint-plugin-nitid'],
  rules: {
    'nitid/use-stylekit': [['font-size', 'font-family'], true],
  },
}
