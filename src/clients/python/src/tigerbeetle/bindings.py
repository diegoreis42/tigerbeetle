##########################################################
## This file was auto-generated by tb_client_header.zig ##
##              Do not manually modify.                 ##
##########################################################
from __future__ import annotations

import ctypes
import enum
from collections.abc import Callable # noqa: TCH003
from typing import Any

from .lib import c_uint128, dataclass, tbclient, validate_uint


class Operation(enum.IntEnum):
    PULSE = 128
    CREATE_ACCOUNTS = 129
    CREATE_TRANSFERS = 130
    LOOKUP_ACCOUNTS = 131
    LOOKUP_TRANSFERS = 132
    GET_ACCOUNT_TRANSFERS = 133
    GET_ACCOUNT_BALANCES = 134
    QUERY_ACCOUNTS = 135
    QUERY_TRANSFERS = 136


class PacketStatus(enum.IntEnum):
    OK = 0
    TOO_MUCH_DATA = 1
    CLIENT_EVICTED = 2
    CLIENT_SHUTDOWN = 3
    INVALID_OPERATION = 4
    INVALID_DATA_SIZE = 5


Client = ctypes.c_void_p

class Status(enum.IntEnum):
    SUCCESS = 0
    UNEXPECTED = 1
    OUT_OF_MEMORY = 2
    ADDRESS_INVALID = 3
    ADDRESS_LIMIT_EXCEEDED = 4
    SYSTEM_RESOURCES = 5
    NETWORK_SUBSYSTEM = 6


class AccountFlags(enum.IntFlag):
    NONE = 0
    LINKED = 1 << 0
    DEBITS_MUST_NOT_EXCEED_CREDITS = 1 << 1
    CREDITS_MUST_NOT_EXCEED_DEBITS = 1 << 2
    HISTORY = 1 << 3
    IMPORTED = 1 << 4
    CLOSED = 1 << 5


class TransferFlags(enum.IntFlag):
    NONE = 0
    LINKED = 1 << 0
    PENDING = 1 << 1
    POST_PENDING_TRANSFER = 1 << 2
    VOID_PENDING_TRANSFER = 1 << 3
    BALANCING_DEBIT = 1 << 4
    BALANCING_CREDIT = 1 << 5
    CLOSING_DEBIT = 1 << 6
    CLOSING_CREDIT = 1 << 7
    IMPORTED = 1 << 8


class AccountFilterFlags(enum.IntFlag):
    NONE = 0
    DEBITS = 1 << 0
    CREDITS = 1 << 1
    REVERSED = 1 << 2


class QueryFilterFlags(enum.IntFlag):
    NONE = 0
    REVERSED = 1 << 0


class CreateAccountResult(enum.IntEnum):
    OK = 0
    LINKED_EVENT_FAILED = 1
    LINKED_EVENT_CHAIN_OPEN = 2
    IMPORTED_EVENT_EXPECTED = 22
    IMPORTED_EVENT_NOT_EXPECTED = 23
    TIMESTAMP_MUST_BE_ZERO = 3
    IMPORTED_EVENT_TIMESTAMP_OUT_OF_RANGE = 24
    IMPORTED_EVENT_TIMESTAMP_MUST_NOT_ADVANCE = 25
    RESERVED_FIELD = 4
    RESERVED_FLAG = 5
    ID_MUST_NOT_BE_ZERO = 6
    ID_MUST_NOT_BE_INT_MAX = 7
    EXISTS_WITH_DIFFERENT_FLAGS = 15
    EXISTS_WITH_DIFFERENT_USER_DATA_128 = 16
    EXISTS_WITH_DIFFERENT_USER_DATA_64 = 17
    EXISTS_WITH_DIFFERENT_USER_DATA_32 = 18
    EXISTS_WITH_DIFFERENT_LEDGER = 19
    EXISTS_WITH_DIFFERENT_CODE = 20
    EXISTS = 21
    FLAGS_ARE_MUTUALLY_EXCLUSIVE = 8
    DEBITS_PENDING_MUST_BE_ZERO = 9
    DEBITS_POSTED_MUST_BE_ZERO = 10
    CREDITS_PENDING_MUST_BE_ZERO = 11
    CREDITS_POSTED_MUST_BE_ZERO = 12
    LEDGER_MUST_NOT_BE_ZERO = 13
    CODE_MUST_NOT_BE_ZERO = 14
    IMPORTED_EVENT_TIMESTAMP_MUST_NOT_REGRESS = 26


class CreateTransferResult(enum.IntEnum):
    OK = 0
    LINKED_EVENT_FAILED = 1
    LINKED_EVENT_CHAIN_OPEN = 2
    IMPORTED_EVENT_EXPECTED = 56
    IMPORTED_EVENT_NOT_EXPECTED = 57
    TIMESTAMP_MUST_BE_ZERO = 3
    IMPORTED_EVENT_TIMESTAMP_OUT_OF_RANGE = 58
    IMPORTED_EVENT_TIMESTAMP_MUST_NOT_ADVANCE = 59
    RESERVED_FLAG = 4
    ID_MUST_NOT_BE_ZERO = 5
    ID_MUST_NOT_BE_INT_MAX = 6
    EXISTS_WITH_DIFFERENT_FLAGS = 36
    EXISTS_WITH_DIFFERENT_PENDING_ID = 40
    EXISTS_WITH_DIFFERENT_TIMEOUT = 44
    EXISTS_WITH_DIFFERENT_DEBIT_ACCOUNT_ID = 37
    EXISTS_WITH_DIFFERENT_CREDIT_ACCOUNT_ID = 38
    EXISTS_WITH_DIFFERENT_AMOUNT = 39
    EXISTS_WITH_DIFFERENT_USER_DATA_128 = 41
    EXISTS_WITH_DIFFERENT_USER_DATA_64 = 42
    EXISTS_WITH_DIFFERENT_USER_DATA_32 = 43
    EXISTS_WITH_DIFFERENT_LEDGER = 67
    EXISTS_WITH_DIFFERENT_CODE = 45
    EXISTS = 46
    ID_ALREADY_FAILED = 68
    FLAGS_ARE_MUTUALLY_EXCLUSIVE = 7
    DEBIT_ACCOUNT_ID_MUST_NOT_BE_ZERO = 8
    DEBIT_ACCOUNT_ID_MUST_NOT_BE_INT_MAX = 9
    CREDIT_ACCOUNT_ID_MUST_NOT_BE_ZERO = 10
    CREDIT_ACCOUNT_ID_MUST_NOT_BE_INT_MAX = 11
    ACCOUNTS_MUST_BE_DIFFERENT = 12
    PENDING_ID_MUST_BE_ZERO = 13
    PENDING_ID_MUST_NOT_BE_ZERO = 14
    PENDING_ID_MUST_NOT_BE_INT_MAX = 15
    PENDING_ID_MUST_BE_DIFFERENT = 16
    TIMEOUT_RESERVED_FOR_PENDING_TRANSFER = 17
    CLOSING_TRANSFER_MUST_BE_PENDING = 64
    AMOUNT_MUST_NOT_BE_ZERO = 18
    LEDGER_MUST_NOT_BE_ZERO = 19
    CODE_MUST_NOT_BE_ZERO = 20
    DEBIT_ACCOUNT_NOT_FOUND = 21
    CREDIT_ACCOUNT_NOT_FOUND = 22
    ACCOUNTS_MUST_HAVE_THE_SAME_LEDGER = 23
    TRANSFER_MUST_HAVE_THE_SAME_LEDGER_AS_ACCOUNTS = 24
    PENDING_TRANSFER_NOT_FOUND = 25
    PENDING_TRANSFER_NOT_PENDING = 26
    PENDING_TRANSFER_HAS_DIFFERENT_DEBIT_ACCOUNT_ID = 27
    PENDING_TRANSFER_HAS_DIFFERENT_CREDIT_ACCOUNT_ID = 28
    PENDING_TRANSFER_HAS_DIFFERENT_LEDGER = 29
    PENDING_TRANSFER_HAS_DIFFERENT_CODE = 30
    EXCEEDS_PENDING_TRANSFER_AMOUNT = 31
    PENDING_TRANSFER_HAS_DIFFERENT_AMOUNT = 32
    PENDING_TRANSFER_ALREADY_POSTED = 33
    PENDING_TRANSFER_ALREADY_VOIDED = 34
    PENDING_TRANSFER_EXPIRED = 35
    IMPORTED_EVENT_TIMESTAMP_MUST_NOT_REGRESS = 60
    IMPORTED_EVENT_TIMESTAMP_MUST_POSTDATE_DEBIT_ACCOUNT = 61
    IMPORTED_EVENT_TIMESTAMP_MUST_POSTDATE_CREDIT_ACCOUNT = 62
    IMPORTED_EVENT_TIMEOUT_MUST_BE_ZERO = 63
    DEBIT_ACCOUNT_ALREADY_CLOSED = 65
    CREDIT_ACCOUNT_ALREADY_CLOSED = 66
    OVERFLOWS_DEBITS_PENDING = 47
    OVERFLOWS_CREDITS_PENDING = 48
    OVERFLOWS_DEBITS_POSTED = 49
    OVERFLOWS_CREDITS_POSTED = 50
    OVERFLOWS_DEBITS = 51
    OVERFLOWS_CREDITS = 52
    OVERFLOWS_TIMEOUT = 53
    EXCEEDS_CREDITS = 54
    EXCEEDS_DEBITS = 55


@dataclass
class Account:
    id: int = 0
    debits_pending: int = 0
    debits_posted: int = 0
    credits_pending: int = 0
    credits_posted: int = 0
    user_data_128: int = 0
    user_data_64: int = 0
    user_data_32: int = 0
    ledger: int = 0
    code: int = 0
    flags: AccountFlags = AccountFlags.NONE
    timestamp: int = 0


@dataclass
class Transfer:
    id: int = 0
    debit_account_id: int = 0
    credit_account_id: int = 0
    amount: int = 0
    pending_id: int = 0
    user_data_128: int = 0
    user_data_64: int = 0
    user_data_32: int = 0
    timeout: int = 0
    ledger: int = 0
    code: int = 0
    flags: TransferFlags = TransferFlags.NONE
    timestamp: int = 0


@dataclass
class CreateAccountsResult:
    index: int = 0
    result: CreateAccountResult = 0


@dataclass
class CreateTransfersResult:
    index: int = 0
    result: CreateTransferResult = 0


@dataclass
class AccountFilter:
    account_id: int = 0
    user_data_128: int = 0
    user_data_64: int = 0
    user_data_32: int = 0
    code: int = 0
    timestamp_min: int = 0
    timestamp_max: int = 0
    limit: int = 0
    flags: AccountFilterFlags = AccountFilterFlags.NONE


@dataclass
class AccountBalance:
    debits_pending: int = 0
    debits_posted: int = 0
    credits_pending: int = 0
    credits_posted: int = 0
    timestamp: int = 0


@dataclass
class QueryFilter:
    user_data_128: int = 0
    user_data_64: int = 0
    user_data_32: int = 0
    ledger: int = 0
    code: int = 0
    timestamp_min: int = 0
    timestamp_max: int = 0
    limit: int = 0
    flags: QueryFilterFlags = QueryFilterFlags.NONE


class CPacket(ctypes.Structure):
    @classmethod
    def from_param(cls, obj):
        validate_uint(bits=8, name="operation", number=obj.operation)
        validate_uint(bits=32, name="data_size", number=obj.data_size)
        validate_uint(bits=32, name="batch_size", number=obj.batch_size)
        return cls(
            next=obj.next,
            user_data=obj.user_data,
            operation=obj.operation,
            status=obj.status,
            data_size=obj.data_size,
            data=obj.data,
            batch_next=obj.batch_next,
            batch_tail=obj.batch_tail,
            batch_size=obj.batch_size,
            batch_allowed=obj.batch_allowed,
        )

CPacket._fields_ = [ # noqa: SLF001
    ("next", ctypes.POINTER(CPacket)),
    ("user_data", ctypes.c_void_p),
    ("operation", ctypes.c_uint8),
    ("status", ctypes.c_uint8),
    ("data_size", ctypes.c_uint32),
    ("data", ctypes.c_void_p),
    ("batch_next", ctypes.POINTER(CPacket)),
    ("batch_tail", ctypes.POINTER(CPacket)),
    ("batch_size", ctypes.c_uint32),
    ("batch_allowed", ctypes.c_bool),
    ("reserved", ctypes.c_uint8 * 7),
]


class CAccount(ctypes.Structure):
    @classmethod
    def from_param(cls, obj):
        validate_uint(bits=128, name="id", number=obj.id)
        validate_uint(bits=128, name="debits_pending", number=obj.debits_pending)
        validate_uint(bits=128, name="debits_posted", number=obj.debits_posted)
        validate_uint(bits=128, name="credits_pending", number=obj.credits_pending)
        validate_uint(bits=128, name="credits_posted", number=obj.credits_posted)
        validate_uint(bits=128, name="user_data_128", number=obj.user_data_128)
        validate_uint(bits=64, name="user_data_64", number=obj.user_data_64)
        validate_uint(bits=32, name="user_data_32", number=obj.user_data_32)
        validate_uint(bits=32, name="ledger", number=obj.ledger)
        validate_uint(bits=16, name="code", number=obj.code)
        validate_uint(bits=64, name="timestamp", number=obj.timestamp)
        return cls(
            id=c_uint128.from_param(obj.id),
            debits_pending=c_uint128.from_param(obj.debits_pending),
            debits_posted=c_uint128.from_param(obj.debits_posted),
            credits_pending=c_uint128.from_param(obj.credits_pending),
            credits_posted=c_uint128.from_param(obj.credits_posted),
            user_data_128=c_uint128.from_param(obj.user_data_128),
            user_data_64=obj.user_data_64,
            user_data_32=obj.user_data_32,
            ledger=obj.ledger,
            code=obj.code,
            flags=obj.flags,
            timestamp=obj.timestamp,
        )


    def to_python(self):
        return Account(
            id=self.id.to_python(),
            debits_pending=self.debits_pending.to_python(),
            debits_posted=self.debits_posted.to_python(),
            credits_pending=self.credits_pending.to_python(),
            credits_posted=self.credits_posted.to_python(),
            user_data_128=self.user_data_128.to_python(),
            user_data_64=self.user_data_64,
            user_data_32=self.user_data_32,
            ledger=self.ledger,
            code=self.code,
            flags=AccountFlags(self.flags),
            timestamp=self.timestamp,
        )

CAccount._fields_ = [ # noqa: SLF001
    ("id", c_uint128),
    ("debits_pending", c_uint128),
    ("debits_posted", c_uint128),
    ("credits_pending", c_uint128),
    ("credits_posted", c_uint128),
    ("user_data_128", c_uint128),
    ("user_data_64", ctypes.c_uint64),
    ("user_data_32", ctypes.c_uint32),
    ("reserved", ctypes.c_uint32),
    ("ledger", ctypes.c_uint32),
    ("code", ctypes.c_uint16),
    ("flags", ctypes.c_uint16),
    ("timestamp", ctypes.c_uint64),
]


class CTransfer(ctypes.Structure):
    @classmethod
    def from_param(cls, obj):
        validate_uint(bits=128, name="id", number=obj.id)
        validate_uint(bits=128, name="debit_account_id", number=obj.debit_account_id)
        validate_uint(bits=128, name="credit_account_id", number=obj.credit_account_id)
        validate_uint(bits=128, name="amount", number=obj.amount)
        validate_uint(bits=128, name="pending_id", number=obj.pending_id)
        validate_uint(bits=128, name="user_data_128", number=obj.user_data_128)
        validate_uint(bits=64, name="user_data_64", number=obj.user_data_64)
        validate_uint(bits=32, name="user_data_32", number=obj.user_data_32)
        validate_uint(bits=32, name="timeout", number=obj.timeout)
        validate_uint(bits=32, name="ledger", number=obj.ledger)
        validate_uint(bits=16, name="code", number=obj.code)
        validate_uint(bits=64, name="timestamp", number=obj.timestamp)
        return cls(
            id=c_uint128.from_param(obj.id),
            debit_account_id=c_uint128.from_param(obj.debit_account_id),
            credit_account_id=c_uint128.from_param(obj.credit_account_id),
            amount=c_uint128.from_param(obj.amount),
            pending_id=c_uint128.from_param(obj.pending_id),
            user_data_128=c_uint128.from_param(obj.user_data_128),
            user_data_64=obj.user_data_64,
            user_data_32=obj.user_data_32,
            timeout=obj.timeout,
            ledger=obj.ledger,
            code=obj.code,
            flags=obj.flags,
            timestamp=obj.timestamp,
        )


    def to_python(self):
        return Transfer(
            id=self.id.to_python(),
            debit_account_id=self.debit_account_id.to_python(),
            credit_account_id=self.credit_account_id.to_python(),
            amount=self.amount.to_python(),
            pending_id=self.pending_id.to_python(),
            user_data_128=self.user_data_128.to_python(),
            user_data_64=self.user_data_64,
            user_data_32=self.user_data_32,
            timeout=self.timeout,
            ledger=self.ledger,
            code=self.code,
            flags=TransferFlags(self.flags),
            timestamp=self.timestamp,
        )

CTransfer._fields_ = [ # noqa: SLF001
    ("id", c_uint128),
    ("debit_account_id", c_uint128),
    ("credit_account_id", c_uint128),
    ("amount", c_uint128),
    ("pending_id", c_uint128),
    ("user_data_128", c_uint128),
    ("user_data_64", ctypes.c_uint64),
    ("user_data_32", ctypes.c_uint32),
    ("timeout", ctypes.c_uint32),
    ("ledger", ctypes.c_uint32),
    ("code", ctypes.c_uint16),
    ("flags", ctypes.c_uint16),
    ("timestamp", ctypes.c_uint64),
]


class CCreateAccountsResult(ctypes.Structure):
    @classmethod
    def from_param(cls, obj):
        validate_uint(bits=32, name="index", number=obj.index)
        return cls(
            index=obj.index,
            result=obj.result,
        )


    def to_python(self):
        return CreateAccountsResult(
            index=self.index,
            result=CreateAccountResult(self.result),
        )

CCreateAccountsResult._fields_ = [ # noqa: SLF001
    ("index", ctypes.c_uint32),
    ("result", ctypes.c_uint32),
]


class CCreateTransfersResult(ctypes.Structure):
    @classmethod
    def from_param(cls, obj):
        validate_uint(bits=32, name="index", number=obj.index)
        return cls(
            index=obj.index,
            result=obj.result,
        )


    def to_python(self):
        return CreateTransfersResult(
            index=self.index,
            result=CreateTransferResult(self.result),
        )

CCreateTransfersResult._fields_ = [ # noqa: SLF001
    ("index", ctypes.c_uint32),
    ("result", ctypes.c_uint32),
]


class CAccountFilter(ctypes.Structure):
    @classmethod
    def from_param(cls, obj):
        validate_uint(bits=128, name="account_id", number=obj.account_id)
        validate_uint(bits=128, name="user_data_128", number=obj.user_data_128)
        validate_uint(bits=64, name="user_data_64", number=obj.user_data_64)
        validate_uint(bits=32, name="user_data_32", number=obj.user_data_32)
        validate_uint(bits=16, name="code", number=obj.code)
        validate_uint(bits=64, name="timestamp_min", number=obj.timestamp_min)
        validate_uint(bits=64, name="timestamp_max", number=obj.timestamp_max)
        validate_uint(bits=32, name="limit", number=obj.limit)
        return cls(
            account_id=c_uint128.from_param(obj.account_id),
            user_data_128=c_uint128.from_param(obj.user_data_128),
            user_data_64=obj.user_data_64,
            user_data_32=obj.user_data_32,
            code=obj.code,
            timestamp_min=obj.timestamp_min,
            timestamp_max=obj.timestamp_max,
            limit=obj.limit,
            flags=obj.flags,
        )


    def to_python(self):
        return AccountFilter(
            account_id=self.account_id.to_python(),
            user_data_128=self.user_data_128.to_python(),
            user_data_64=self.user_data_64,
            user_data_32=self.user_data_32,
            code=self.code,
            timestamp_min=self.timestamp_min,
            timestamp_max=self.timestamp_max,
            limit=self.limit,
            flags=AccountFilterFlags(self.flags),
        )

CAccountFilter._fields_ = [ # noqa: SLF001
    ("account_id", c_uint128),
    ("user_data_128", c_uint128),
    ("user_data_64", ctypes.c_uint64),
    ("user_data_32", ctypes.c_uint32),
    ("code", ctypes.c_uint16),
    ("reserved", ctypes.c_uint8 * 58),
    ("timestamp_min", ctypes.c_uint64),
    ("timestamp_max", ctypes.c_uint64),
    ("limit", ctypes.c_uint32),
    ("flags", ctypes.c_uint32),
]


class CAccountBalance(ctypes.Structure):
    @classmethod
    def from_param(cls, obj):
        validate_uint(bits=128, name="debits_pending", number=obj.debits_pending)
        validate_uint(bits=128, name="debits_posted", number=obj.debits_posted)
        validate_uint(bits=128, name="credits_pending", number=obj.credits_pending)
        validate_uint(bits=128, name="credits_posted", number=obj.credits_posted)
        validate_uint(bits=64, name="timestamp", number=obj.timestamp)
        return cls(
            debits_pending=c_uint128.from_param(obj.debits_pending),
            debits_posted=c_uint128.from_param(obj.debits_posted),
            credits_pending=c_uint128.from_param(obj.credits_pending),
            credits_posted=c_uint128.from_param(obj.credits_posted),
            timestamp=obj.timestamp,
        )


    def to_python(self):
        return AccountBalance(
            debits_pending=self.debits_pending.to_python(),
            debits_posted=self.debits_posted.to_python(),
            credits_pending=self.credits_pending.to_python(),
            credits_posted=self.credits_posted.to_python(),
            timestamp=self.timestamp,
        )

CAccountBalance._fields_ = [ # noqa: SLF001
    ("debits_pending", c_uint128),
    ("debits_posted", c_uint128),
    ("credits_pending", c_uint128),
    ("credits_posted", c_uint128),
    ("timestamp", ctypes.c_uint64),
    ("reserved", ctypes.c_uint8 * 56),
]


class CQueryFilter(ctypes.Structure):
    @classmethod
    def from_param(cls, obj):
        validate_uint(bits=128, name="user_data_128", number=obj.user_data_128)
        validate_uint(bits=64, name="user_data_64", number=obj.user_data_64)
        validate_uint(bits=32, name="user_data_32", number=obj.user_data_32)
        validate_uint(bits=32, name="ledger", number=obj.ledger)
        validate_uint(bits=16, name="code", number=obj.code)
        validate_uint(bits=64, name="timestamp_min", number=obj.timestamp_min)
        validate_uint(bits=64, name="timestamp_max", number=obj.timestamp_max)
        validate_uint(bits=32, name="limit", number=obj.limit)
        return cls(
            user_data_128=c_uint128.from_param(obj.user_data_128),
            user_data_64=obj.user_data_64,
            user_data_32=obj.user_data_32,
            ledger=obj.ledger,
            code=obj.code,
            timestamp_min=obj.timestamp_min,
            timestamp_max=obj.timestamp_max,
            limit=obj.limit,
            flags=obj.flags,
        )


    def to_python(self):
        return QueryFilter(
            user_data_128=self.user_data_128.to_python(),
            user_data_64=self.user_data_64,
            user_data_32=self.user_data_32,
            ledger=self.ledger,
            code=self.code,
            timestamp_min=self.timestamp_min,
            timestamp_max=self.timestamp_max,
            limit=self.limit,
            flags=QueryFilterFlags(self.flags),
        )

CQueryFilter._fields_ = [ # noqa: SLF001
    ("user_data_128", c_uint128),
    ("user_data_64", ctypes.c_uint64),
    ("user_data_32", ctypes.c_uint32),
    ("ledger", ctypes.c_uint32),
    ("code", ctypes.c_uint16),
    ("reserved", ctypes.c_uint8 * 6),
    ("timestamp_min", ctypes.c_uint64),
    ("timestamp_max", ctypes.c_uint64),
    ("limit", ctypes.c_uint32),
    ("flags", ctypes.c_uint32),
]


# Don't be tempted to use c_char_p for bytes_ptr - it's for null terminated strings only.
OnCompletion = ctypes.CFUNCTYPE(None, ctypes.c_void_p, Client, ctypes.POINTER(CPacket),
                                ctypes.c_uint64, ctypes.c_void_p, ctypes.c_uint32)

# Initialize a new TigerBeetle client which connects to the addresses provided and
# completes submitted packets by invoking the callback with the given context.
tb_client_init = tbclient.tb_client_init
tb_client_init.restype = Status
tb_client_init.argtypes = [ctypes.POINTER(Client), ctypes.POINTER(ctypes.c_uint8 * 16),
                           ctypes.c_char_p, ctypes.c_uint32, ctypes.c_void_p,
                           OnCompletion]

# Initialize a new TigerBeetle client which echos back any data submitted.
tb_client_init_echo = tbclient.tb_client_init_echo
tb_client_init_echo.restype = Status
tb_client_init_echo.argtypes = [ctypes.POINTER(Client), ctypes.POINTER(ctypes.c_uint8 * 16),
                                ctypes.c_char_p, ctypes.c_uint32, ctypes.c_void_p,
                                OnCompletion]

# Closes the client, causing any previously submitted packets to be completed with
# `TB_PACKET_CLIENT_SHUTDOWN` before freeing any allocated client resources from init.
# It is undefined behavior to use any functions on the client once deinit is called.
tb_client_deinit = tbclient.tb_client_deinit
tb_client_deinit.restype = None
tb_client_deinit.argtypes = [Client]

# Submit a packet with its operation, data, and data_size fields set.
# Once completed, `on_completion` will be invoked with `on_completion_ctx` and the given
# packet on the `tb_client` thread (separate from caller's thread).
tb_client_submit = tbclient.tb_client_submit
tb_client_submit.restype = None
tb_client_submit.argtypes = [Client, ctypes.POINTER(CPacket)]
class AsyncStateMachineMixin:
    _submit: Callable[[Operation, Any, Any, Any], Any]
    async def create_accounts(self, accounts: list[Account]) -> list[CreateAccountsResult]:
        return await self._submit(
            Operation.CREATE_ACCOUNTS,
            accounts,
            CAccount,
            CCreateAccountsResult,
        )

    async def create_transfers(self, transfers: list[Transfer]) -> list[CreateTransfersResult]:
        return await self._submit(
            Operation.CREATE_TRANSFERS,
            transfers,
            CTransfer,
            CCreateTransfersResult,
        )

    async def lookup_accounts(self, accounts: list[int]) -> list[Account]:
        return await self._submit(
            Operation.LOOKUP_ACCOUNTS,
            accounts,
            c_uint128,
            CAccount,
        )

    async def lookup_transfers(self, transfers: list[int]) -> list[Transfer]:
        return await self._submit(
            Operation.LOOKUP_TRANSFERS,
            transfers,
            c_uint128,
            CTransfer,
        )

    async def get_account_transfers(self, filter: AccountFilter) -> list[Transfer]:
        return await self._submit(
            Operation.GET_ACCOUNT_TRANSFERS,
            [filter],
            CAccountFilter,
            CTransfer,
        )

    async def get_account_balances(self, filter: AccountFilter) -> list[AccountBalance]:
        return await self._submit(
            Operation.GET_ACCOUNT_BALANCES,
            [filter],
            CAccountFilter,
            CAccountBalance,
        )

    async def query_accounts(self, query_filter: QueryFilter) -> list[Account]:
        return await self._submit(
            Operation.QUERY_ACCOUNTS,
            [query_filter],
            CQueryFilter,
            CAccount,
        )

    async def query_transfers(self, query_filter: QueryFilter) -> list[Transfer]:
        return await self._submit(
            Operation.QUERY_TRANSFERS,
            [query_filter],
            CQueryFilter,
            CTransfer,
        )



class StateMachineMixin:
    _submit: Callable[[Operation, Any, Any, Any], Any]
    def create_accounts(self, accounts: list[Account]) -> list[CreateAccountsResult]:
        return self._submit(
            Operation.CREATE_ACCOUNTS,
            accounts,
            CAccount,
            CCreateAccountsResult,
        )

    def create_transfers(self, transfers: list[Transfer]) -> list[CreateTransfersResult]:
        return self._submit(
            Operation.CREATE_TRANSFERS,
            transfers,
            CTransfer,
            CCreateTransfersResult,
        )

    def lookup_accounts(self, accounts: list[int]) -> list[Account]:
        return self._submit(
            Operation.LOOKUP_ACCOUNTS,
            accounts,
            c_uint128,
            CAccount,
        )

    def lookup_transfers(self, transfers: list[int]) -> list[Transfer]:
        return self._submit(
            Operation.LOOKUP_TRANSFERS,
            transfers,
            c_uint128,
            CTransfer,
        )

    def get_account_transfers(self, filter: AccountFilter) -> list[Transfer]:
        return self._submit(
            Operation.GET_ACCOUNT_TRANSFERS,
            [filter],
            CAccountFilter,
            CTransfer,
        )

    def get_account_balances(self, filter: AccountFilter) -> list[AccountBalance]:
        return self._submit(
            Operation.GET_ACCOUNT_BALANCES,
            [filter],
            CAccountFilter,
            CAccountBalance,
        )

    def query_accounts(self, query_filter: QueryFilter) -> list[Account]:
        return self._submit(
            Operation.QUERY_ACCOUNTS,
            [query_filter],
            CQueryFilter,
            CAccount,
        )

    def query_transfers(self, query_filter: QueryFilter) -> list[Transfer]:
        return self._submit(
            Operation.QUERY_TRANSFERS,
            [query_filter],
            CQueryFilter,
            CTransfer,
        )



