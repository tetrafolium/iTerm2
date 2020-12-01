"""Represents tmux integration objects."""
import abc
import typing

import iterm2.api_pb2
import iterm2.connection
import iterm2.rpc
import iterm2.session
import iterm2.transaction
import iterm2.tab
import iterm2.window


@abc.abstractmethod
class Delegate:
    """Delegate interface for tmux."""
    async def tmux_delegate_async_get_window_for_tab_id(
            self, tab_id: str) -> typing.Optional[iterm2.window.Window]:
        """Refreshes and gets the window for the specified tab."""

    def tmux_delegate_get_session_by_id(
            self, session_id: str) -> typing.Optional[iterm2.session.Session]:
        """Returns the session with the given ID."""

    def tmux_delegate_get_connection(self) -> iterm2.connection.Connection:
        """Returns the connection."""


DELEGATE: typing.Optional[Delegate] = None
DELEGATE_FACTORY: typing.Optional[
    typing.Callable[
        [iterm2.connection.Connection],
        typing.Awaitable[Delegate]]] = None


class TmuxException(Exception):
    """A problem was encountered in a Tmux request."""


class TmuxConnection:
    """
    A tmux integration connection.

    Do not create this yourself. Use :func:`async_get_tmux_connections`,
    instead.
    """

    def __init__(self, connection_id, owning_session_id, delegate):
        self.__connection_id = connection_id
        self.__owning_session_id = owning_session_id
        self.__delegate = delegate

    @property
    def connection_id(self) -> str:
        """Returns the unique identifier of the connection.

        :returns: A connection ID, which is also a human-readable description
            of the connection.
        """
        return self.__connection_id

    @property
    def owning_session(self) -> typing.Optional['iterm2.session.Session']:
        """Returns the "gateway" session.

        :returns: The :class:`~iterm2.Session` where `tmux -CC` was run, or
            `None` if it cannot be found."""
        return self.__delegate.tmux_delegate_get_session_by_id(
            self.__owning_session_id)

    async def async_send_command(self, command: str) -> str:
        """Sends a command to the tmux server.

        This may not be called from within a :class:`~iterm2.Transaction`.

        :param command: The command to send to tmux (e.g., "list-sessions")

        :returns: The command's output as a string.

        :throws TmuxException: If the command fails for any reason or the RPC
            fails such as from an invalid ID.

        .. seealso:: Example ":ref:`tile_example`"
        """
        response = await iterm2.rpc.async_rpc_send_tmux_command(
            self.__delegate.tmux_delegate_get_connection(),
            self.__connection_id,
            command)
        # pylint: disable=no-member
        if (response.tmux_response.status == iterm2.api_pb2.TmuxResponse.
                Status.Value("OK")):
            if response.tmux_response.send_command.HasField("output"):
                return response.tmux_response.send_command.output
            raise TmuxException("Tmux reported an error")
        raise TmuxException(
            iterm2.api_pb2.TmuxResponse.Status.Name(
                response.tmux_response.status))

    async def async_set_tmux_window_visible(
            self, tmux_window_id: str, visible: bool) -> None:
        """Hides or shows a tmux window.

        Tmux windows are represented as tabs in iTerm2. You can get a
        tmux_window_id from :meth:`~iterm2.Tab.tmux_window_id`. If this tab is
        attached to a tmux session, then it may be hidden.

        This may not be called from within a :class:`~iterm2.Transaction`.

        :param tmux_window_id: The window to show or hide.
        :param visible: `True` to show a window, `False` to hide a window.
        """
        response = await iterm2.rpc.async_rpc_set_tmux_window_visible(
            self.__delegate.tmux_delegate_get_connection(),
            self.__connection_id,
            tmux_window_id,
            visible)
        # pylint: disable=no-member
        if (response.tmux_response.status != iterm2.api_pb2.TmuxResponse.
                Status.Value("OK")):
            raise TmuxException(
                iterm2.api_pb2.TmuxResponse.Status.Name(
                    response.tmux_response.status))

    async def async_create_window(self) -> 'iterm2.window.Window':
        """Creates a new tmux window.

        This may not be called from within a :class:`~iterm2.Transaction`.

        :returns: A new :class:`Window`.

        .. seealso:: Example ":ref:`tmux_example`"
        """
        response = await iterm2.rpc.async_rpc_create_tmux_window(
            self.__delegate.tmux_delegate_get_connection(),
            self.__connection_id)
        # pylint: disable=no-member
        if (response.tmux_response.status != iterm2.api_pb2.TmuxResponse.
                Status.Value("OK")):
            raise TmuxException(
                iterm2.api_pb2.TmuxResponse.Status.Name(
                    response.tmux_response.status))
        tab_id = response.tmux_response.create_window.tab_id
        return await self.__delegate.tmux_delegate_async_get_window_for_tab_id(
            tab_id)


async def async_get_tmux_connections(
        connection: iterm2.connection.Connection) -> typing.List[
            TmuxConnection]:
    """Fetches a list of tmux connections.

    This may not be called from within a :class:`~iterm2.Transaction`.

    :param connection: The connection to iTerm2.
    :returns: The current tmux connections.

    .. seealso:: Example ":ref:`tmux_example`"
    """
    # Work around a bad design that we're stuck with because this is a public
    # API. Before, tmux depended on app. That was cyclic. The cycle was broken
    # by adding a delegate, but you can call this before creating App. The
    # solution is to use a delegate factory so we can make an App just in time
    # without tmux knowing about it.
    global DELEGATE  # pylint: disable=global-statement
    if not DELEGATE:
        assert DELEGATE_FACTORY
        DELEGATE = await DELEGATE_FACTORY(connection)

    response = await iterm2.rpc.async_rpc_list_tmux_connections(connection)
    # pylint: disable=no-member
    if (response.tmux_response.status ==
            iterm2.api_pb2.TmuxResponse.Status.Value("OK")):
        def make_connection(proto):
            return TmuxConnection(proto.connection_id,
                                  proto.owning_session_id,
                                  DELEGATE)
        return list(map(make_connection,
                        response.tmux_response.list_connections.connections))
    raise TmuxException(
        iterm2.api_pb2.TmuxResponse.Status.Name(
            response.tmux_response.status))


async def async_get_tmux_connection_by_connection_id(
        connection: iterm2.connection.Connection,
        connection_id: str) -> typing.Optional[TmuxConnection]:
    """Find a tmux connection by its ID.

    :param connection: The connection to iTerm2.
    :param connection_id: A connection ID for a :class:`TmuxConnection`.

    :returns: Either a :class:`TmuxConnection` or `None`.
    """
    connections = await async_get_tmux_connections(connection)
    for candidate in connections:
        if candidate.connection_id == connection_id:
            return candidate
    return None
