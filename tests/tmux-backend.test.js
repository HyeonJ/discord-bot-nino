jest.mock('child_process', () => ({
  execSync: jest.fn(),
}));

describe('tmux backend transport', () => {
  let childProcess;
  let tmux;

  beforeEach(() => {
    jest.resetModules();
    childProcess = require('child_process');
    childProcess.execSync.mockReset();
    tmux = require('../src/backends/tmux');
  });

  test('checkSession calls tmux has-session for the session', () => {
    childProcess.execSync.mockReturnValue(Buffer.from(''));

    expect(tmux.checkSession('nino')).toBe(true);

    expect(childProcess.execSync).toHaveBeenCalledWith("tmux has-session -t 'nino' 2>/dev/null");
  });

  test('sendKeys escapes single quotes safely before sending enter', () => {
    childProcess.execSync.mockReturnValue(Buffer.from(''));

    expect(tmux.sendKeys('nino', "don't stop")).toBe(true);

    expect(childProcess.execSync).toHaveBeenCalledWith(
      "tmux send-keys -t 'nino' -- 'don'\\''t stop' C-m"
    );
  });

  test('sendKeys returns false for tmux not found or missing session errors', () => {
    childProcess.execSync.mockImplementation(() => {
      throw new Error("can't find session: nino");
    });

    expect(tmux.sendKeys('nino', 'hello')).toBe(false);
  });

  test('sendKeys returns false for generic execSync failures', () => {
    childProcess.execSync.mockImplementation(() => {
      throw new Error('permission denied');
    });

    expect(tmux.sendKeys('nino', 'hello')).toBe(false);
  });

  test('getChildPid looks up child process using the provider process pattern', () => {
    childProcess.execSync
      .mockReturnValueOnce(Buffer.from('1234\n'))
      .mockReturnValueOnce(Buffer.from('5678\n'));

    expect(tmux.getChildPid('nino', 'claude')).toBe(5678);

    expect(childProcess.execSync).toHaveBeenNthCalledWith(
      1,
      "tmux list-panes -t 'nino' -F '#{pane_pid}' 2>/dev/null"
    );
    expect(childProcess.execSync).toHaveBeenNthCalledWith(
      2,
      "pgrep -P 1234 -f 'claude' 2>/dev/null || echo \"\""
    );
  });

  test('getChildPid returns null when no provider process is found', () => {
    childProcess.execSync
      .mockReturnValueOnce(Buffer.from('1234\n'))
      .mockReturnValueOnce(Buffer.from('\n'));

    expect(tmux.getChildPid('nino', 'claude')).toBeNull();
  });
});
