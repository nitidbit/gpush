module.exports = {
  customSyntax: 'postcss-scss',
  extends: ['stylelint-prettier/recommended'],
  plugins: ['./stylelint_plugin_nitid_use_stylekit'],
  rules: {
    'nitid/use-stylekit': [['font-size', 'font-family'], true],
  },
}
